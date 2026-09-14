from pathlib import Path
from copy import deepcopy
import shutil
import json

import numpy as np
import torch

from lerobot.datasets.lerobot_dataset import LeRobotDataset
from lerobot.utils.constants import DEFAULT_FEATURES


SRC = Path(
    "/home/liuyy/workplace/projects/huawei-cloudrobo-2026/"
    "datasets/site_clear_table_good_20260912"
)

DST = Path(
    "/home/liuyy/workplace/projects/huawei-cloudrobo-2026/"
    "datasets/site_clear_table_good_10fps_20260912"
)

SRC_REPO = "site_clear_table_good_20260912"
DST_REPO = "site_clear_table_good_10fps_20260912"

SOURCE_FPS = 30
TARGET_FPS = 10
STRIDE = SOURCE_FPS // TARGET_FPS


# ------------------------------------------------------------
# 1. 检查源数据
# ------------------------------------------------------------
if not (SRC / "meta" / "info.json").is_file():
    raise FileNotFoundError(
        f"源数据不存在或不完整：{SRC / 'meta' / 'info.json'}"
    )

if DST.exists():
    print(f"删除旧输出目录: {DST}")
    shutil.rmtree(DST)


# ------------------------------------------------------------
# 2. 加载 30 FPS 数据集
# ------------------------------------------------------------
print("加载源数据集...")

src = LeRobotDataset(
    repo_id=SRC_REPO,
    root=SRC,
    video_backend="pyav",
    return_uint8=True,
)

print("Source episodes :", src.meta.total_episodes)
print("Source frames   :", src.meta.total_frames)
print("Source FPS      :", src.meta.fps)
print("Robot type      :", src.meta.robot_type)

assert src.meta.total_episodes == 38, (
    f"应该有 38 episodes，实际为 {src.meta.total_episodes}"
)

assert src.meta.fps == 30, (
    f"源数据应该是 30 FPS，实际为 {src.meta.fps}"
)


# ------------------------------------------------------------
# 3. 获取 task
# ------------------------------------------------------------
if src.meta.tasks is None or len(src.meta.tasks) == 0:
    raise RuntimeError("源数据集中没有 task 信息")

tasks = list(src.meta.tasks.index)

if len(tasks) != 1:
    raise RuntimeError(
        f"当前脚本预期只有一个 task，但检测到: {tasks}"
    )

task = str(tasks[0])

print("Task:", task)


# ------------------------------------------------------------
# 4. 创建目标 features
#
# timestamp / frame_index / episode_index / index / task_index
# 等字段由 LeRobot 自动重新生成。
# ------------------------------------------------------------
features = {
    k: deepcopy(v)
    for k, v in src.meta.features.items()
    if k not in DEFAULT_FEATURES
}

# 删除旧视频编码信息，避免继承 30 FPS 视频 metadata。
# 新视频保存后 LeRobot 会重新生成。
for key, ft in features.items():
    if ft.get("dtype") == "video":
        ft.pop("info", None)
        ft.pop("video_info", None)

video_keys = set(src.meta.video_keys)

print("Video keys:", sorted(video_keys))


# ------------------------------------------------------------
# 5. 创建新的 10 FPS 数据集
# ------------------------------------------------------------
dst = LeRobotDataset.create(
    repo_id=DST_REPO,
    root=DST,
    fps=TARGET_FPS,
    robot_type=src.meta.robot_type,
    features=features,
    use_videos=True,
    video_backend="pyav",
    streaming_encoding=True,
    encoder_queue_maxsize=120,
)


def to_numpy(x):
    if torch.is_tensor(x):
        return x.detach().cpu().numpy()
    return np.asarray(x)


def prepare_video_frame(x):
    arr = to_numpy(x)

    # LeRobot reader 通常返回 C,H,W；
    # writer 需要 H,W,C。
    if (
        arr.ndim == 3
        and arr.shape[0] in (1, 3, 4)
        and arr.shape[-1] not in (1, 3, 4)
    ):
        arr = np.moveaxis(arr, 0, -1)

    if arr.dtype != np.uint8:
        if np.issubdtype(arr.dtype, np.floating):
            if arr.size > 0 and arr.max() <= 1.0001:
                arr = arr * 255.0

        arr = np.clip(arr, 0, 255).astype(np.uint8)

    return np.ascontiguousarray(arr)


# ------------------------------------------------------------
# 6. 每个 episode 每 3 帧取 1 帧
#
# 30 FPS:
# frame 0,1,2,3,4,5...
#
# 10 FPS:
# frame 0,3,6,9,12...
# ------------------------------------------------------------
total_written = 0

for ep_idx in range(src.meta.total_episodes):
    ep = src.meta.episodes[ep_idx]

    start = int(ep["dataset_from_index"])
    stop = int(ep["dataset_to_index"])

    src_count = stop - start
    dst_count = 0

    for src_idx in range(start, stop, STRIDE):
        item = src[src_idx]

        frame = {
            "task": task,
        }

        for key in features:
            value = item[key]

            if key in video_keys:
                frame[key] = prepare_video_frame(value)
            else:
                frame[key] = to_numpy(value)

        dst.add_frame(frame)
        dst_count += 1

    dst.save_episode()

    total_written += dst_count

    print(
        f"[{ep_idx + 1:02d}/{src.meta.total_episodes}] "
        f"{src_count} frames @30fps -> "
        f"{dst_count} frames @10fps"
    )


# ------------------------------------------------------------
# 7. 完成数据集
# ------------------------------------------------------------
dst.finalize()

print()
print("========================================")
print("10 FPS 数据集生成完成")
print("========================================")
print("Output:", DST)
print("Episodes:", src.meta.total_episodes)
print("Frames:", total_written)
print("FPS:", TARGET_FPS)


# ------------------------------------------------------------
# 8. 检查最终 info.json
# ------------------------------------------------------------
info_path = DST / "meta" / "info.json"

with open(info_path, "r", encoding="utf-8") as f:
    info = json.load(f)

assert info["total_episodes"] == 38, info["total_episodes"]
assert info["fps"] == 10, info["fps"]
assert info["total_frames"] == total_written

print()
print("最终 metadata 校验通过")
print("total_episodes =", info["total_episodes"])
print("total_frames   =", info["total_frames"])
print("fps            =", info["fps"])
print("robot_type     =", info.get("robot_type"))

print()
print("SUCCESS")
