#!/bin/bash

# 日志函数
log() {
    local level="$1"
    shift
    local message="$@"
    local timestamp=$(date +'%Y-%m-%d %H:%M:%S')

    # 颜色定义
    local color_reset='\033[0m'
    local color_info='\033[0;32m'
    local color_warn='\033[0;33m'
    local color_error='\033[0;31m'
    local color_debug='\033[0;36m'

    case "$level" in
        "info"|"INFO")
            echo -e "${color_info}[INFO] [${timestamp}] ${message}${color_reset}"
            ;;
        "warn"|"WARN"|"warning"|"WARNING")
            echo -e "${color_warn}[WARN] [${timestamp}] ${message}${color_reset}"
            ;;
        "error"|"ERROR")
            echo -e "${color_error}[ERROR] [${timestamp}] ${message}${color_reset}" >&2
            ;;
        "debug"|"DEBUG")
            echo -e "${color_debug}[DEBUG] [${timestamp}] ${message}${color_reset}"
            ;;
        *)
            echo -e "[UNKNOWN] [${timestamp}] ${level} ${message}"
            ;;
    esac
}

load_images() {
    log "info" "[start] Loading ${IMAGE_NAME}:${IMAGE_TAG} image"
    
    if [[ ! -f "$IMAGE_PATH" ]]; then
        log "error" "Image file not found at: $IMAGE_PATH"
        return 1
    fi

    # 优先尝试 docker load (适用于 docker save 保存的 tar 包)
    if docker load -i "$IMAGE_PATH"; then
        log "info" "[success] Image loaded successfully using docker load"
        return 0
    fi
    
    log "warn" "docker load failed, trying docker import..."
    # 备选 docker import (适用于文件系统归档)
    if ! docker import "$IMAGE_PATH" "$IMAGE_NAME:$IMAGE_TAG"; then
        log "error" "Failed to import Docker image from $IMAGE_PATH"
        return 1
    fi
    log "info" "[success] ${IMAGE_NAME}:${IMAGE_TAG} image loading completed"
}

start_docker() {
  # 检查必要变量
  if [[ -z "$IMAGE_NAME" || -z "$IMAGE_TAG" || -z "$CONTAINER_NAME" ]]; then
      log "error" "Missing required variables: IMAGE_NAME, IMAGE_TAG, or CONTAINER_NAME"
      return 1
  fi

  log "info" "[start] Start lifting the training container"

  
  # 1. 检查 docker 服务是否正常运行
  if ! docker info &> /dev/null; then
    log "error" "Docker is not running. Please start Docker manually."
    return 1
  fi
  
  # 2. 检查 docker 镜像是否存在
  if docker image inspect "${IMAGE_NAME}:${IMAGE_TAG}" &> /dev/null; then
    log "info" "${IMAGE_NAME}:${IMAGE_TAG} model image exists"
  else
    log "info" "Image not found locally, loading from file..."
    load_images || return 1
  fi

  # 3. 检查并清理同名旧容器
  if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
      log "warn" "Container ${CONTAINER_NAME} already exists. Removing it..."
      docker rm -f "${CONTAINER_NAME}"
  fi

  log "info" "Set Docker container startup parameters"
  
  # 4. 构建 NPU 设备参数
  local device_args=()
  if [ -n "$NPUS" ]; then
      IFS=',' read -ra ADDR <<< "$NPUS"
      for i in "${ADDR[@]}"; do
        device_args+=("--device=/dev/davinci$i")
      done
  fi

  local docker_run_flags=(-d)
  if [[ -t 0 && -t 1 ]]; then
    docker_run_flags=(-dit)
  fi

  # 5. 准备 Docker 参数数组 (使用数组比字符串拼接更安全、更易读)
  # 注意: --shm-size 对于分布式训练很重要，建议显式设置或依赖 --ipc=host
  #      --privileged 或 --cap-add=SYS_PTRACE 可能需要用于 NPU 驱动访问
  local docker_run_cmd=(
      docker run "${docker_run_flags[@]}"
      --ipc=host
      --net=host
      --privileged
      --shm-size=32g
      --ulimit memlock=-1
      --ulimit stack=67108864
      --name="${CONTAINER_NAME}"
      "${device_args[@]}"
      --device=/dev/davinci_manager
      --device=/dev/devmm_svm
      --device=/dev/hisi_hdc
      -v /etc/ascend_install.info:/etc/ascend_install.info
      -v /etc/hccn.conf:/etc/hccn.conf
      -v /usr/local/Ascend/driver:/usr/local/Ascend/driver
      -v /usr/local/Ascend/add-ons/:/usr/local/Ascend/add-ons
      -v /usr/local/dcmi:/usr/local/dcmi
      -v /usr/local/Ascend/driver/tools/hccn_tool:/usr/local/Ascend/driver/tools/hccn_tool
      -v /usr/local/Ascend/driver/lib64/:/usr/local/Ascend/driver/lib64/
      -v /usr/local/Ascend/driver/version.info:/usr/local/Ascend/driver/version.info
      -v /root/.cache:/root/.cache
  )

  # 自动检测 npu-smi 路径并挂载
  if [ -f "/usr/local/bin/npu-smi" ]; then
    docker_run_cmd+=("-v" "/usr/local/bin/npu-smi:/usr/local/bin/npu-smi")
  elif [ -f "/usr/local/sbin/npu-smi" ]; then
    docker_run_cmd+=("-v" "/usr/local/sbin/npu-smi:/usr/local/sbin/npu-smi")
  fi

  # 6. 添加共享目录挂载
  if [[ -n "${SHARE_PATH_HOST}" ]]; then
    docker_run_cmd+=("-v" "${SHARE_PATH_HOST}:${SHARE_PATH_CONTAINER}")
  fi

  # 7. 添加镜像和命令
  docker_run_cmd+=("${IMAGE_NAME}:${IMAGE_TAG}" /bin/bash)

  log "info" "Start the container with command: ${docker_run_cmd[*]}"
  
  # 启动docker容器
  if "${docker_run_cmd[@]}"; then
    log "info" "[success] The container ${CONTAINER_NAME} is successfully started"
  else
    log "error" "[failed] Failed to start container"
    return 1
  fi
}
