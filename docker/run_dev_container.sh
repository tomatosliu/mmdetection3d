#!/bin/bash
#
# Create a docker container on given docker image and set up basic user
# development environment.

set -e

IMG=mmdetection3d
NAME=$1

# The directory contains current script.
DIR=$(dirname $(realpath "$BASH_SOURCE"))
REPO_DIR=$(dirname $DIR)
WORK_DIR_IN_CONTAINER=/$(basename $REPO_DIR)

# Check if the container exists.
if docker ps -a --format "{{.Names}}" | grep -q "^$NAME$"; then
  echo >&2 "Container [$NAME] is already existing"
  echo >&2 "Run 'docker stop $NAME && docker rm $NAME' before creating new one"
  exit
fi

echo "Creating container [$NAME] on image [$IMG] ..."
echo "Bind mount [$REPO_DIR] as [$WORK_DIR_IN_CONTAINER] in the container"

# Prepare cache path.
mkdir -pv $HOME/.cache

DOCKER_RUN_EXTRA_OPTIONS=""
# Check if specified ports to be published.
# For example: PORTS=8080,9000-9100
if [[ -n $PORTS ]]; then
  echo "Publish ports: $PORTS"
  for port in $(echo $PORTS | tr ',' '\n'); do
    DOCKER_RUN_EXTRA_OPTIONS+=" -p $port:$port "
  done
elif ! $ROOTLESS; then
  echo "Use host networking"
  DOCKER_RUN_EXTRA_OPTIONS+=" --net host "
fi
# Check if needs ssh.
if [[ -n $SSH_PORT ]]; then
  echo "Publish ssh port 22 as: $SSH_PORT"
  DOCKER_RUN_EXTRA_OPTIONS+=" -p $SSH_PORT:22 "
fi
# Check if the image has CUDA.
if docker inspect --format='{{.Config.Env}}' $IMG | grep -q "CUDA_VERSION="; then
  # NOTE: Need to install NVIDIA driver and NVIDIA Container Toolkit. See
  # https://github.com/NVIDIA/nvidia-docker.
  echo "Found CUDA version: $(docker inspect --format='{{.Config.Env}}' $IMG |
    sed 's/.*CUDA_VERSION=\([.0-9]*\).*/\1/')"
  DOCKER_RUN_EXTRA_OPTIONS+="\
  --gpus all \
  -e NVIDIA_VISIBLE_DEVICES=all \
  -e NVIDIA_DRIVER_CAPABILITIES=all \
"
fi
# Check if in bazel workspace.
if [[ -f $REPO_DIR/WORKSPACE ]]; then
  echo "Found Bazel workspace"
  DOCKER_RUN_EXTRA_OPTIONS+=" -v $HOME/.cache/bazel:$HOME/.cache/bazel "
  if [[ -n $ROOTLESS_USER && $ROOTLESS_USER != $USER ]]; then
    # Allow Docker Rootless to `mkdir $HOME/.cache/bazel`.
    chmod -v 777 $HOME/.cache
    # Allow Docker Rootless to create bazel-* symbolic links.
    chmod -v 777 $REPO_DIR
  fi
fi

# Create container.
docker run -it -d --name $NAME \
  --privileged \
  --hostname in_docker \
  --add-host in_docker:127.0.0.1 \
  --add-host $(hostname):127.0.0.1 \
  --shm-size 2G \
  -e DISPLAY \
  -v /dev/bus/usb:/dev/bus/usb \
  -v /etc/localtime:/etc/localtime:ro \
  -v /lib/modules:/lib/modules \
  -v /media:/media \
  -v /mnt:/mnt \
  -v /tmp/.X11-unix:/tmp/.X11-unix \
  -v /usr/src:/usr/src \
  -v $HOME/.cache:$DOCKER_HOME/.cache \
  -v $REPO_DIR:$WORK_DIR_IN_CONTAINER \
  -w $WORK_DIR_IN_CONTAINER \
  $DOCKER_RUN_EXTRA_OPTIONS \
  $IMG \
  /bin/bash

echo "Container [$NAME] has been created"
