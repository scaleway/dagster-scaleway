from typing import TYPE_CHECKING, Any, Mapping, NamedTuple, Optional, Sequence, cast

from dagster import (
    Field,
    _check as check,
)
from dagster._config import process_config
from dagster._core.container_context import process_shared_container_context_config
from dagster._core.errors import DagsterInvalidConfigError
from dagster._core.storage.dagster_run import DagsterRun

from scaleway_core.bridge.region import REGION_FR_PAR

if TYPE_CHECKING:
    from . import ScalewayServerlessJobRunLauncher

SCALEWAY_SERVERLESS_JOB_CONTEXT_SCHEMA = {
    "docker_image": Field(
        str,
        is_required=False,  # Can also be specified at the repository level or via a tag
        description="The docker image to use for the serverless job",
    ),
    "env_vars": Field(
        [str],
        is_required=False,
        description=(
            "The list of environment variables names to include in the Job Definition. "
            "Each can be of the form KEY=VALUE or just KEY (in which case the value will be pulled "
            "from the local environment)"
        ),
    ),
    "region": Field(
        str,
        is_required=False,
        default_value=REGION_FR_PAR,
        description="The region to use for the serverless job",
    ),
    "memory_limit": Field(
        int,
        is_required=False,
        description="The memory limit in MiB for the serverless job",
    ),
    "cpu_limit": Field(
        int,
        is_required=False,
        description="The CPU limit in mCPU for the serverless job",
    ),
}

DEFAULT_CPU_LIMIT = 1000
DEFAULT_MEMORY_LIMIT = 512


class ScalewayServerlessJobContext(
    NamedTuple(
        "_ScalewayServerlessJobContext",
        [
            ("docker_image", Optional[str]),
            ("env_vars", Sequence[str]),
            ("region", str),
            ("memory_limit", int),
            ("cpu_limit", int),
        ],
    )
):
    """Encapsulates the configuration for a Scaleway Serverless Job.
    Dagster code. Can be set at the instance level (via config in the `DockerRunLauncher`),
    repository location level, and at the individual step level (for runs using the
    `docker_executor` to run each op in its own container). Config at each of these lower levels is
    merged in with any config set at a higher level, following the policy laid out in the
    merge() method below.
    """

    def __new__(
        cls,
        docker_image: Optional[str] = None,
        env_vars: Optional[Sequence[str]] = None,
        region: Optional[str] = None,
        memory_limit: Optional[int] = None,
        cpu_limit: Optional[int] = None,
    ):
        return super(ScalewayServerlessJobContext, cls).__new__(
            cls,
            docker_image=check.opt_str_param(docker_image, "docker_image"),
            env_vars=check.opt_sequence_param(env_vars, "env_vars", of_type=str),
            region=check.opt_str_param(region, "region"),
            memory_limit=check.opt_int_param(
                memory_limit, "memory_limit", DEFAULT_MEMORY_LIMIT
            ),
            cpu_limit=check.opt_int_param(cpu_limit, "cpu_limit", DEFAULT_CPU_LIMIT),
        )

    def merge(self, other: "ScalewayServerlessJobContext"):
        # Combines config set at a higher level with overrides/additions that are set at a lower
        # level. For example, a certain set of config set in the `DockerRunLauncher`` can be
        # combined with config set at the step level in the `docker_executor`.
        # Lists of env vars and secrets are appended, the registry is replaced, and the
        # `container_kwargs` field does a shallow merge so that different kwargs can be combined
        # or replaced without replacing the full set of arguments.
        return ScalewayServerlessJobContext(
            docker_image=other.docker_image
            if other.docker_image is not None
            else self.docker_image,
            env_vars=[*self.env_vars, *other.env_vars],
            region=other.region if other.region is not None else self.region,
            memory_limit=other.memory_limit
            if other.memory_limit is not None
            else self.memory_limit,
            cpu_limit=other.cpu_limit
            if other.cpu_limit is not None
            else self.cpu_limit,
        )

    @staticmethod
    def create_for_run(
        dagster_run: DagsterRun,
        run_launcher: Optional["ScalewayServerlessJobRunLauncher"],
    ):
        context = ScalewayServerlessJobContext()

        # First apply the instance / run_launcher-level context
        if run_launcher:
            context = context.merge(
                ScalewayServerlessJobContext(
                    docker_image=run_launcher.docker_image,
                    env_vars=run_launcher.env_vars,
                    region=run_launcher.region,
                    memory_limit=run_launcher.memory_limit,
                    cpu_limit=run_launcher.cpu_limit,
                )
            )

        run_container_context = (
            dagster_run.job_code_origin.repository_origin.container_context
            if dagster_run.job_code_origin
            else None
        )

        if not run_container_context:
            return context

        return context.merge(
            ScalewayServerlessJobContext.create_from_config(run_container_context)
        )

    @staticmethod
    def create_from_config(run_container_context):
        processed_shared_container_context = process_shared_container_context_config(
            run_container_context or {}
        )
        shared_container_context = ScalewayServerlessJobContext(
            env_vars=processed_shared_container_context.get("env_vars", [])
        )

        run_docker_container_context = (
            run_container_context.get("docker", {}) if run_container_context else {}
        )

        if not run_docker_container_context:
            return shared_container_context

        processed_container_context = process_config(
            SCALEWAY_SERVERLESS_JOB_CONTEXT_SCHEMA, run_docker_container_context
        )

        if not processed_container_context.success:
            raise DagsterInvalidConfigError(
                "Errors while parsing Docker container context",
                processed_container_context.errors,
                run_docker_container_context,
            )

        processed_context_value = cast(
            Mapping[str, Any], processed_container_context.value
        )

        return shared_container_context.merge(
            ScalewayServerlessJobContext(
                docker_image=processed_context_value.get("docker_image"),
                env_vars=processed_context_value.get("env_vars", []),
                region=processed_context_value.get("region", REGION_FR_PAR),
                memory_limit=processed_context_value.get(
                    "memory_limit", DEFAULT_MEMORY_LIMIT
                ),
                cpu_limit=processed_context_value.get("cpu_limit", DEFAULT_CPU_LIMIT),
            )
        )
