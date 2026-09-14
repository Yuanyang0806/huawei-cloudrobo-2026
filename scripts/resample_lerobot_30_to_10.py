#!/usr/bin/env python3

from pathlib import Path
from copy import deepcopy
import shutil

import numpy as np
import torch
from tqdm import tqdm

from lerobot.datasets import LeRobotDataset


SRC = Path.home() / "workplace/projects/huawei-cloudrobo-2026/datasets/site_clear_table_final_20260911"
DST = Path.home() / "workplace/projects/huawei-cloudrobo-2026/datasets/site_clear_table_final_10fps_20260912"

SRC_REPO = "liuyy/site_clear_table_final_20260911"
DST_REPO = "liuyy/site_clear_table_final_10fps_20260912"

TARGET_FPS = 10


if DST.exists():
    raise RuntimeError(
        f"\n输出目录已经存在：\n{DST}\n"
        "为避免误删数据，请先手动确认后删除或更换输出目录。"
    )

print("========================================")
print("Loading source dataset")
print("========================================")

src = LeRobotDataset(
    repo_id=SRC_REPO,
    root=SRC,
    video_backend="pyav",
    return_uint8=True,
)

source_fps = int(src.meta.fps)

print("source fps      =", source_fps)
print("source episodes =", src.num_episodes)
print("source frames   =", src.num_frames)

if source_fps % TARGET_FPS != 0:
    raise RuntimeError(
        f"当前脚本只处理整数倍降采样：{source_fps} -> {TARGET_FPS}"
    )

STRIDE = source_fps // TARGET_FPS

print("target fps      =", TARGET_FPS)
print("stride          =", STRIDE)

# timestamp / frame_index / episode_index / index / task_index
# 由 LeRobot Writer 自动重新生成，不能手工传给 add_frame。
AUTO_FEATURES = {
    "timestamp",
    "frame_index",
    "episode_index",
    "index",
    "task_index",
}

features = deepcopy(src.features)

for key in AUTO_FEATURES:
    features.pop(key, None)

camera_keys = set(src.meta.camera_keys)

print("\nFeatures copied to new dataset:")
for key, value in features.items():
    print(" ", key, value.get("shape"), value.get("dtype"))

print("\nCameras:")
for key in camera_keys:
    print(" ", key)

robot_type = getattr(src.meta, "robot_type", None)

print("\n========================================")
print("Creating target dataset")
print("========================================")

dst = LeRobotDataset.create(
    repo_id=DST_REPO,
    root=DST,
    fps=TARGET_FPS,
    features=features,
    robot_type=robot_type,
    use_videos=True,

    # 直接边读取边编码视频，避免先生成十几万张临时 PNG。
    streaming_encoding=True,
    encoder_queue_maxsize=120,
    encoder_threads=4,
)

# 先只读取 parquet 中的 episode_index，不触发视频解码。
episode_indices = np.asarray(
    src.hf_dataset["episode_index"],
    dtype=np.int64,
)

episodes = sorted(np.unique(episode_indices).tolist())

expected_frames = 0

for ep in episodes:

    source_positions = np.flatnonzero(episode_indices == ep)

    # 30 -> 10 FPS:
    # frame 0,3,6,9,...
    selected_positions = source_positions[::STRIDE]

    expected_frames += len(selected_positions)

    print(
        f"\nEpisode {ep:02d}: "
        f"{len(source_positions)} -> {len(selected_positions)} frames"
    )

    for idx in tqdm(
        selected_positions,
        desc=f"episode {ep}",
        leave=False,
    ):
        item = src[int(idx)]

        frame = {}

        for key in features:
            value = item[key]

            if isinstance(value, torch.Tensor):
                value = value.detach().cpu().numpy()

            # LeRobot reader 的视频帧是 CHW。
            # Writer 需要普通图像 HWC。
            if key in camera_keys:
                value = np.asarray(value)

                if (
                    value.ndim == 3
                    and value.shape[0] in (1, 3, 4)
                ):
                    value = np.transpose(value, (1, 2, 0))

                value = np.ascontiguousarray(value)

            frame[key] = value

        # task 文本必须保留。
        frame["task"] = item["task"]

        dst.add_frame(frame)

    dst.save_episode()

    print(
        f"Saved target episode {ep}: "
        f"{len(selected_positions)} frames"
    )


dst.finalize()

print("\n========================================")
print("CONVERSION FINISHED")
print("========================================")
print("output =", DST)
print("episodes =", len(episodes))
print("expected frames =", expected_frames)
print("target fps =", TARGET_FPS)
