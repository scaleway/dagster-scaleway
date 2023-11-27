import argparse
import os
import subprocess

INPUT_JSON = os.getenv("INPUT_JSON")

parser = argparse.ArgumentParser()
parser.add_argument(
    "wrapped", nargs=argparse.REMAINDER, help="The wrapped Dagster CLI command"
)


def main():
    args = parser.parse_args()

    if not INPUT_JSON:
        print("INPUT_JSON not set")
        exit(1)

    with subprocess.Popen(
        args.wrapped + [INPUT_JSON],
        env=os.environ,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    ) as proc:
        for line in proc.stdout:
            print(line.decode("utf8"))

        if proc.returncode:
            exit(proc.returncode)
