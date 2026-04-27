# 模型脚本环境变量介绍

以上模型列表中脚本的环境变量说明具体如下：

| 环境变量名称                    | 环境变量描述                                                            | 使用示例                                                 | 使用建议                                                                          |
| :------------------------------ | :---------------------------------------------------------------------- | :------------------------------------------------------- | :-------------------------------------------------------------------------------- |
| **ASCEND_LAUNCH_BLOCKING**      | 1：强制算子采用同步模式运行，屏蔽 task_queue 优化；0：默认异步模式。    | `export ASCEND_LAUNCH_BLOCKING=1`                        | 仅用于调试定位算子报错问题，**生产环境建议关闭（0）**，否则严重影响性能。         |
| **ASCEND_RT_VISIBLE_DEVICES**   | 指定当前进程可见的 NPU 设备 ID。                                        | `export ASCEND_RT_VISIBLE_DEVICES=0,1,2,3`               | 用于单机多卡或指定卡运行，容器环境中常由调度系统自动注入。                        |
| **ASCEND_SLOG_PRINT_TO_STDOUT** | 0：关闭日志打屏（默认）；1：开启日志打屏。                              | `export ASCEND_SLOG_PRINT_TO_STDOUT=1`                   | 仅用于调试，**生产环境建议关闭**，以免大量日志输出影响性能。                      |
| **CLOSE_MATMUL_K_SHIFT**        | 关闭 Matmul K 维度偏移优化。                                            | `export CLOSE_MATMUL_K_SHIFT=1`                          | 仅在遇到特定精度问题或算子错误时尝试开启。                                        |
| **COMBINED_ENABLE**             | 设置 combined 标志，优化非连续算子组合。0：关闭；1：开启。              | `export COMBINED_ENABLE=1`                               | 建议开启以优化特定场景性能。                                                      |
| **CPU_AFFINITY_CONF**           | 开启粗/细粒度绑核。                                                     | `export CPU_AFFINITY_CONF=1`                             | **建议开启**以减少线程间抢占和调度开销，提升性能。                                |
| **CUDA_DEVICE_MAX_CONNECTIONS** | 任务流映射到的硬件队列数量。                                            | `export CUDA_DEVICE_MAX_CONNECTIONS=1`                   | 在 MindSpeed-LLM 中**通常设置为 1** 以优化性能。                                  |
| **GLOO_SOCKET_IFNAME**          | 指定 Gloo Socket 通信网卡接口名。                                       | `export GLOO_SOCKET_IFNAME=eth0`                         | 通常与管理网口一致，用于非数据平面的通信。                                        |
| **HCCL_ALGO**                   | 配置 HCCL 集合通信算法。                                                | `export HCCL_ALGO="alltoall=level0:NA;level1:pipeline"`  | 针对特定集合通信算子（如 AlltoAll）进行调优。                                     |
| **HCCL_ASYNC_ERROR_HANDLING**   | HCCL 异步错误处理开关。0：关闭；1：开启（默认）。                       | `export HCCL_ASYNC_ERROR_HANDLING=1`                     | 保持默认开启即可，有助于故障定位。                                                |
| **HCCL_BUFFSIZE**               | 设置 HCCL 通信缓冲区大小（单位 MB）。                                   | `export HCCL_BUFFSIZE=200`                               | 根据显存余量和通信需求调整，常见值为 200。                                        |
| **HCCL_CONNECT_TIMEOUT**        | 设置 HCCL 建链超时时间，默认 120 秒。                                   | `export HCCL_CONNECT_TIMEOUT=1800`                       | 大模型初始化时间较长，**建议设置为 1200 秒以上**（如 1800, 3600），避免超时失败。 |
| **HCCL_DETERMINISTIC**          | 开启确定性计算模式。                                                    | `export HCCL_DETERMINISTIC=true`                         | 需要**复现实验结果**时开启，可能会对性能有一定影响。                              |
| **HCCL_EXEC_TIMEOUT**           | 设置 HCCL 集合通信执行超时时间。                                        | `export HCCL_EXEC_TIMEOUT=5600`                          | 防止通信长时间挂起，建议根据模型规模和网络状况适当调大。                          |
| **HCCL_IF_BASE_PORT**           | 设置 HCCL 通信基础端口。                                                | `export HCCL_IF_BASE_PORT=48890`                         | 避免端口冲突时使用，通常由系统自动分配。                                          |
| **HCCL_LOGIC_SUPERPOD_ID**      | 指定逻辑超节点 ID（0-N）。                                              | `export HCCL_LOGIC_SUPERPOD_ID=0`                        | 用于多机超节点网络拓扑配置。                                                      |
| **HCCL_OP_BASE_FFTS_MODE**      | 开启基于 FFTS 模式的算子运行。                                          | `export HCCL_OP_BASE_FFTS_MODE=TRUE`                     | 特定硬件/算子优化选项，视具体模型需求开启。                                       |
| **HCCL_OP_RETRY_ENABLE**        | 开启 HCCL 算子重试机制。                                                | `export HCCL_OP_RETRY_ENABLE="L0:0, L1:1, L2:1"`         | 增强网络波动场景下的训练稳定性。                                                  |
| **HCCL_SOCKET_IFNAME**          | 指定 HCCL Socket 通信网卡接口名。                                       | `export HCCL_SOCKET_IFNAME=eth0`                         | 需指定为支持 RoCE 的高速网卡接口名，确保多机通信性能。                            |
| **HCCL_WHITELIST_DISABLE**      | HCCL 白名单开关。1：关闭；0：开启。                                     | `export HCCL_WHITELIST_DISABLE=1`                        | 通常保持默认，特殊场景需关闭白名单时使用。                                        |
| **MULTI_STREAM_MEMORY_REUSE**   | 开启多流内存复用。                                                      | `export MULTI_STREAM_MEMORY_REUSE=1`                     | 开启后可减少内存占用，需配合 `STREAMS_PER_DEVICE` 使用。                          |
| **NPU_ASD_ENABLE**              | 特征值检测功能开关。0：关闭；1/2/3：开启不同级别。                      | `export NPU_ASD_ENABLE=0`                                | 训练稳定后**建议关闭**以减少性能损耗，调试精度问题时可开启。                      |
| **NPUS_PER_NODE**               | 配置单节点使用的 NPU 数量。                                             | `export NPUS_PER_NODE=8`                                 | 根据实际硬件配置设置，通常为 8。                                                  |
| **PYTORCH_NPU_ALLOC_CONF**      | NPU 内存分配配置，主要用于碎片优化。                                    | `export PYTORCH_NPU_ALLOC_CONF=expandable_segments:True` | **强烈建议开启 `expandable_segments:True`** 以减少内存碎片，降低 OOM 风险。       |
| **STREAMS_PER_DEVICE**          | 设置每台 NPU 的流数量。                                                 | `export STREAMS_PER_DEVICE=32`                           | 配合多流内存复用使用，常见值为 32。                                               |
| **TASK_QUEUE_ENABLE**           | 控制 task_queue 算子下发队列优化等级。0：关闭；1：Level 1；2：Level 2。 | `export TASK_QUEUE_ENABLE=2`                             | **建议开启 Level 2 优化**以提升性能。                                             |
| **TORCH_HCCL_ZERO_COPY**        | 开启 Torch HCCL 零拷贝功能。                                            | `export TORCH_HCCL_ZERO_COPY=1`                          | 优化通信性能，减少内存拷贝。                                                      |
