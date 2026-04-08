#!/usr/bin/env python3
"""
提取4500P计算节点带内管理IP信息

功能：
1. 读取 "4500P计算节点带内管理IP.csv" 和 "node_list.txt"
2. 对于node_list中的每个节点，在CSV中找到对应的设备编号
3. 找出满足在同一个框架内设备数>=8的节点
4. 输出结果到 "4500P计算节点带内管理IP_提取结果.csv"
"""

import csv
from collections import defaultdict


def read_node_list(file_path):
    """读取节点列表文件，提取设备编号"""
    node_device_ids = []
    node_mapping = {}  # device_id -> node_name

    with open(file_path, 'r', encoding='utf-8') as f:
        for line in f:
            node_name = line.strip()
            if node_name:
                # 从bms0001提取数字部分作为设备编号
                device_id = int(node_name.replace('bms', ''))
                node_device_ids.append(device_id)
                node_mapping[device_id] = node_name

    return node_device_ids, node_mapping


def read_csv_data(file_path):
    """读取CSV文件数据"""
    data = {}
    with open(file_path, 'r', encoding='utf-8') as f:
        reader = csv.reader(f)

        for row in reader:
            if len(row) >= 7:
                device_id = int(row[0])
                data[device_id] = {
                    '设备编号': row[0],
                    '框ID': row[1],
                    '设备框内ID': row[2],
                    '设备名': row[3],
                    'IP地址': row[4],
                    '掩码': row[5],
                    '网关': row[6]
                }
    return data


def filter_frames_with_min_devices(node_device_ids, csv_data, min_count=8):
    """
    筛选出满足条件的设备：
    - 设备编号在node_list中
    - 同一框ID下的设备数量 >= min_count
    """
    # 统计每个框ID下有多少个设备在node_list中
    frame_device_count = defaultdict(int)
    frame_devices = defaultdict(list)  # 框ID -> [(device_id, device_info), ...]

    for device_id in node_device_ids:
        if device_id in csv_data:
            frame_id = csv_data[device_id]['框ID']
            frame_device_count[frame_id] += 1
            frame_devices[frame_id].append((device_id, csv_data[device_id]))

    # 筛选出框内设备数>=min_count的框
    valid_frames = {
        frame_id
        for frame_id, count in frame_device_count.items() if count >= min_count
    }

    # 收集所有满足条件的设备
    result = []
    for frame_id in valid_frames:
        for device_id, device_info in frame_devices[frame_id]:
            result.append((device_id, device_info))

    # 按设备编号排序
    result.sort(key=lambda x: x[0])

    return result


def write_output(result, node_mapping, output_path):
    """写入输出CSV文件"""
    with open(output_path, 'w', newline='', encoding='utf-8') as f:
        writer = csv.writer(f)
        # 写入表头
        writer.writerow(
            ['设备编号', '设备名(bms名称)', '框ID', '设备框内ID', '设备名', 'IP地址', '掩码', '网关'])

        # 写入数据
        for device_id, device_info in result:
            bms_name = node_mapping.get(device_id, f'bms{device_id:04d}')
            writer.writerow([
                device_info['设备编号'], bms_name, device_info['框ID'],
                device_info['设备框内ID'], device_info['设备名'], device_info['IP地址'],
                device_info['掩码'], device_info['网关']
            ])


def write_bms_list(result, node_mapping, output_path):
    """将设备名(bms名称)写入txt文件，每行一个"""
    with open(output_path, 'w', encoding='utf-8') as f:
        for device_id, device_info in result:
            bms_name = node_mapping.get(device_id, f'bms{device_id:04d}')
            f.write(bms_name + '\n')


def main():
    # 文件路径
    csv_file = '4500P计算节点带内管理IP.csv'
    node_file = 'node_list.txt'
    output_file = '4500P计算节点带内管理IP_提取结果.csv'

    print(f'读取节点列表: {node_file}')
    node_device_ids, node_mapping = read_node_list(node_file)
    print(f'共找到 {len(node_device_ids)} 个节点')

    print(f'读取CSV数据: {csv_file}')
    csv_data = read_csv_data(csv_file)
    print(f'共找到 {len(csv_data)} 条设备记录')

    print('筛选满足条件的设备（同一框内>=8个设备）...')
    result = filter_frames_with_min_devices(node_device_ids,
                                            csv_data,
                                            min_count=16)
    print(f'满足条件的设备数量: {len(result)}')

    # 统计每个框ID的设备数
    frame_stats = defaultdict(int)
    for device_id, device_info in result:
        frame_stats[device_info['框ID']] += 1

    print('\n各框ID设备统计:')
    for frame_id in sorted(frame_stats.keys(), key=int):
        print(f'  框ID {frame_id}: {frame_stats[frame_id]} 个设备')

    print(f'\n写入输出文件: {output_file}')
    write_output(result, node_mapping, output_file)

    # 写入bms列表txt文件
    bms_list_file = 'result_node_list_bms.txt'
    print(f'写入BMS列表文件: {bms_list_file}')
    write_bms_list(result, node_mapping, bms_list_file)

    print('处理完成!')


if __name__ == '__main__':
    main()
