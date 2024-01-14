from typing import Any, Mapping, Optional

import dagster._check as check
from dagster._core.launcher.base import (
    CheckRunHealthResult,
    LaunchRunContext,
    ResumeRunContext,
    RunLauncher,
    WorkerStatus,
)
from dagster._core.origin import JobPythonOrigin
from dagster._core.storage.dagster_run import DagsterRun
from dagster._core.storage.tags import DOCKER_IMAGE_TAG
from dagster._core.utils import parse_env_var
from dagster._grpc.types import ExecuteRunArgs, ResumeRunArgs
from dagster._serdes import ConfigurableClass
from dagster._serdes.config_class import ConfigurableClassData
from typing_extensions import Self


import scaleway.jobs.v1alpha1 as scw
import scaleway

from .serverless_job_context import (
    ScalewayServerlessJobContext,
    SCALEWAY_SERVERLESS_JOB_CONTEXT_SCHEMA,
)

SERVERLESS_JOBS_RUN_ID = "scaleway/serverless-jobs/run-id"
SERVERLESS_JOBS_DEFINITION_ID = "scaleway/serverless-jobs/definition-id"

COMMAND_WRAPPER = "dagster-scaleway"

SERVERLESS_JOBS_STATES_TO_WORKER_STATUS = {
    scw.JobRunState.QUEUED: WorkerStatus.RUNNING,
    scw.JobRunState.RUNNING: WorkerStatus.RUNNING,
    scw.JobRunState.SUCCEEDED: WorkerStatus.SUCCESS,
    scw.JobRunState.FAILED: WorkerStatus.FAILED,
    scw.JobRunState.UNKNOWN_STATE: WorkerStatus.UNKNOWN,
}


class ScalewayServerlessJobRunLauncher(RunLauncher, ConfigurableClass):
    """Launches runs as Scaleway Serverless Jobs."""

    def __init__(
        self,
        inst_data: Optional[ConfigurableClassData] = None,
        docker_image: Optional[str] = None,
        # See ScalewayServerlessJobContext for more details on how env_vars are handled
        env_vars: Optional[list[str]] = None,
        region: Optional[str] = None,
        memory_limit: Optional[int] = None,
        cpu_limit: Optional[int] = None,
    ):
        self._inst_data = inst_data
        self.docker_image = docker_image
        self.env_vars = env_vars
        self.region = region
        self.memory_limit = memory_limit
        self.cpu_limit = cpu_limit

        super().__init__()

    @property
    def inst_data(self):
        return self._inst_data

    @classmethod
    def config_type(cls):
        return SCALEWAY_SERVERLESS_JOB_CONTEXT_SCHEMA

    @classmethod
    def from_config_value(
        cls, inst_data: ConfigurableClassData, config_value: Mapping[str, Any]
    ) -> Self:
        return ScalewayServerlessJobRunLauncher(inst_data=inst_data, **config_value)

    def get_serverless_job_context(
        self, dagster_run: DagsterRun
    ) -> ScalewayServerlessJobContext:
        return ScalewayServerlessJobContext.create_for_run(dagster_run, self)

    def _get_client(
        self, serverless_job_context: ScalewayServerlessJobContext
    ) -> scaleway.Client:
        # TODO?: is support config file useful? We might want to be able to provide the Scaleway config
        # directly in the dagster config. In that case, we'll need to add the complete config in ScalewayServerlessJobContext
        # for now, we'll use environment variables
        client = scaleway.Client.from_config_file_and_env()
        if serverless_job_context.region:
            client.default_region = serverless_job_context.region
        return client

    def _get_docker_image(self, job_code_origin: JobPythonOrigin) -> str:
        docker_image = job_code_origin.repository_origin.container_image

        if not docker_image:
            docker_image = self.docker_image

        if not docker_image:
            raise RuntimeError(
                "No docker image specified by the instance config or repository"
            )

        return docker_image

    def _get_semantic_job_name(self, dagster_run: DagsterRun) -> str:
        """Slightly hacky way to get the semantic job name.
        Makes it easier to find the job in the Scaleway console.
        """
        if dagster_run.op_selection:
            return list(dagster_run.op_selection)[-1]
        if dagster_run.asset_selection:
            return list(dagster_run.asset_selection)[-1].to_user_string()
        return dagster_run.run_id

    def _create_or_update_job_definition(
        self,
        client: scaleway.Client,
        run: DagsterRun,
        docker_image: str,
        command: list[str],
    ) -> scw.JobDefinition:
        serverless_job_context = self.get_serverless_job_context(run)
        api = scw.JobsV1Alpha1API(client)

        job_def_env = dict(
            [parse_env_var(env_var) for env_var in serverless_job_context.env_vars]
        )
        job_def_env["DAGSTER_RUN_JOB_NAME"] = run.job_name
        job_def_env["DAGSTER_RUN_ID"] = run.run_id
        job_def_env["INPUT_JSON"] = command[-1]

        api = scw.JobsV1Alpha1API(client)

        wrapped_command = [COMMAND_WRAPPER] + command[:-1]
        description = (
            f"JobDefinition for {run.job_name}."
            + " "
            + "Created by the ServerlessJobRunLauncher from dagster-scaleway."
        )
        job_def_name = self._get_semantic_job_name(run)

        for job_def in api.list_job_definitions(page=1, page_size=100).job_definitions:
            if job_def.name != run.job_name:
                continue

            job_def = api.update_job_definition(
                job_definition_id=job_def.id,
                name=job_def_name,
                image_uri=docker_image,
                environment_variables=job_def_env,
                command=" ".join(wrapped_command),
                memory_limit=serverless_job_context.memory_limit,
                cpu_limit=serverless_job_context.cpu_limit,
                description=description,
            )

            self._instance.report_engine_event(
                message=f"Updated job {job_def.id} for Dagster run {run.run_id}",
                dagster_run=run,
                cls=self.__class__,
            )

            return job_def

        job_def = api.create_job_definition(
            name=job_def_name,
            image_uri=docker_image,
            environment_variables=job_def_env,
            command=" ".join(wrapped_command),
            memory_limit=serverless_job_context.memory_limit,
            cpu_limit=serverless_job_context.cpu_limit,
            description=description,
            project_id=client.default_project_id,
        )

        self._instance.report_engine_event(
            message=f"Created job {job_def.id} for Dagster run {run.run_id}",
            dagster_run=run,
            cls=self.__class__,
        )

        return job_def

    def _launch_serverless_job_with_command(
        self, run: DagsterRun, docker_image: str, command: list[str]
    ):
        serverless_job_context = self.get_serverless_job_context(run)
        client = self._get_client(serverless_job_context)
        api = scw.JobsV1Alpha1API(client)

        job_def = self._create_or_update_job_definition(
            client, run, docker_image, command
        )

        job_run = api.start_job_definition(job_definition_id=job_def.id)

        self._instance.report_engine_event(
            message=f"Started job definition {job_def.name} with run id {job_run.id} for Dagster run {run.run_id}",
            dagster_run=run,
            cls=self.__class__,
        )

        self._instance.add_run_tags(
            run.run_id,
            {
                SERVERLESS_JOBS_RUN_ID: job_run.id,
                SERVERLESS_JOBS_DEFINITION_ID: job_def.id,
                DOCKER_IMAGE_TAG: docker_image,
            },
        )

    def launch_run(self, context: LaunchRunContext) -> None:
        run = context.dagster_run
        job_code_origin = check.not_none(context.job_code_origin)
        docker_image = self._get_docker_image(job_code_origin)

        command = ExecuteRunArgs(
            job_origin=job_code_origin,
            run_id=run.run_id,
            instance_ref=self._instance.get_ref(),
        ).get_command_args()

        self._launch_serverless_job_with_command(run, docker_image, command)

    @property
    def supports_resume_run(self):
        # TODO?: check if we can resume a run
        return True

    def resume_run(self, context: ResumeRunContext) -> None:
        run = context.dagster_run
        job_code_origin = check.not_none(context.job_code_origin)
        docker_image = self._get_docker_image(job_code_origin)

        command = ResumeRunArgs(
            job_origin=job_code_origin,
            run_id=run.run_id,
            instance_ref=self._instance.get_ref(),
        ).get_command_args()

        self._launch_serverless_job_with_command(run, docker_image, command)

    def _get_scaleway_job_run_from_dagster_run(self, run) -> Optional[scw.JobRun]:
        if not run or run.is_finished:
            return None

        job_run_id = run.tags.get(SERVERLESS_JOBS_RUN_ID)

        if not job_run_id:
            return None

        serverless_job_context = self.get_serverless_job_context(run)
        client = self._get_client(serverless_job_context)
        api = scw.JobsV1Alpha1API(client)

        try:
            return api.get_job_run(job_run_id=job_run_id)
        except scaleway.ScalewayException:
            return None

    def terminate(self, run_id):
        run = self._instance.get_run_by_id(run_id)

        if not run:
            return False

        self._instance.report_run_canceling(run)

        job_run = self._get_scaleway_job_run_from_dagster_run(run)

        if not job_run:
            self._instance.report_engine_event(
                message=f"Unable to get Scaleway job run for Dagster run {run_id} to send termination signal",
                dagster_run=run,
                cls=self.__class__,
            )
            return False

        if job_run.state != scw.JobRunState.RUNNING:
            self._instance.report_engine_event(
                message=f"Scaleway job run {job_run.id} for Dagster run {run_id} is not running, cannot terminate",
                dagster_run=run,
                cls=self.__class__,
            )
            return False

        serverless_job_context = self.get_serverless_job_context(run)
        client = self._get_client(serverless_job_context)
        api = scw.JobsV1Alpha1API(client)

        api.stop_job_run(job_run_id=job_run.id)

        return True

    @property
    def supports_check_run_worker_health(self):
        return True

    def check_run_worker_health(self, run: DagsterRun):
        job_run = self._get_scaleway_job_run_from_dagster_run(run)
        if job_run is None:
            return CheckRunHealthResult(
                WorkerStatus.NOT_FOUND,
                run_worker_id=run.run_id,
                msg=f"Unable to find Scaleway job run with id {run.run_id} for Dagster run {run.run_id}",
            )

        health = CheckRunHealthResult(run_worker_id=run.run_id)
        health.transient = job_run.state in scw.JOB_RUN_TRANSIENT_STATUSES
        health.status = SERVERLESS_JOBS_STATES_TO_WORKER_STATUS.get(
            job_run.state, WorkerStatus.UNKNOWN
        )

        if job_run.error_message:
            health.msg = job_run.error_message

        return health
