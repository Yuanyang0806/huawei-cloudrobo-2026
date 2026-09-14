# Huawei CloudRobo 2026

2026 华为云具身智能大赛真机项目归档仓库。

本项目围绕 **GALAXEA A1Z 六轴机械臂 + G1Z 夹爪**，完成从真机遥操作数据采集、LeRobot 数据整理、云端 π0.5 策略训练，到通过 Huawei CloudRobo R2C SDK 进行真机在线推理与动作下发的完整流程。

最终主要任务为桌面清理（Clear the Table）：机械臂根据双目 RGB 观测识别桌面上的可移动物体，并依次抓取、放入指定收纳篮中。

## Target stack

- Ubuntu 24.04
- GALAXEA A1Z + G1Z
- Python 3.12
- LeRobot 0.6.1
- Huawei CloudRobo R2C SDK
- Cloud-hosted π0.5 policy
- Intel RealSense L515 external camera
- Intel RealSense D405 wrist camera
- SocketCAN / CAN 1 Mbps

## System overview

```text
Star-Arm-102 leader
        │
        │ teleoperation
        ▼
GALAXEA A1Z + G1Z
        │
        ├── cam_external (L515)
        ├── cam_wrist    (D405)
        └── 6 arm joints + gripper
        │
        ▼
LeRobot 0.6.1
  data collection / dataset
        │
        ▼
Huawei CloudRobo
  π0.5 training & model service
        │
        ▼
R2C SDK / cloudroboclient
 observation uplink → cloud inference → action downlink
        │
        ▼
GALAXEA A1Z real-robot execution
```

## Main work completed

- Adapted GALAXEA A1Z + G1Z to the LeRobot 0.6.1 hardware interface.
- Integrated Star-Arm-102 as the teleoperation leader for real-robot demonstrations.
- Collected 30 FPS demonstrations with two RGB observations:
  - `observation.images.cam_external`
  - `observation.images.cam_wrist`
- Standardized the robot state/action space as 7 dimensions: six arm joints plus gripper.
- Completed dataset review, cleaning, merging and resampling experiments.
- Trained and deployed a cloud-hosted π0.5 vision-language-action policy.
- Integrated Huawei CloudRobo through the R2C SDK for observation uplink, cloud inference and action downlink.
- Debugged real-hardware issues including CAN initialization, camera device mapping, D405 exposure, leader/follower joint signs, gripper direction, execution frequency, joint velocity limits and automatic return-to-zero behavior.
- Verified end-to-end real-robot inference on the A1Z platform.

## Repository structure

```text
configs/       Runtime, robot and R2C configuration files
scripts/       Camera, dataset and hardware utility scripts
third_party/   GALAXEA-A1Z SDK and a1z-teleop submodules
env/           Environment-related files
src/           Competition notes and final-site reference documents
```

The large real-robot datasets, trained model artifacts, credentials and runtime logs are intentionally not stored in this repository.

## Key conventions

For the final A1Z pipeline, the robot observation/action convention is:

```text
state/action: [arm_joint1, arm_joint2, arm_joint3,
               arm_joint4, arm_joint5, arm_joint6,
               gripper]
```

Camera naming used by LeRobot:

```text
cam_external -> observation.images.cam_external
cam_wrist    -> observation.images.cam_wrist
```

R2C transport-side image channels:

```text
cam_external -> images.color.front
cam_wrist    -> images.color.wrist
```

The final demonstrations were collected at 30 FPS, with robot joint values/actions represented in radians for the training and inference pipeline.

## Related links

- [Huawei CloudRobo documentation](https://support.huaweicloud.com/cloudrobo/)
- [CloudRobo: GALAXEA A1Z integration guide](https://support.huaweicloud.com/sdkreference-cloudrobo/zh-cn_topic_0000002713194086.html)
- [CloudRobo: Agent debugging](https://support.huaweicloud.com/sdkreference-cloudrobo/cloudrobo_03_0005.html)
- [GALAXEA A1Z Python SDK](https://github.com/userguide-galaxea/GALAXEA-A1Z)
- [a1z-teleop](https://github.com/suhanwu/a1z-teleop)
- [Hugging Face LeRobot documentation](https://huggingface.co/docs/lerobot/)
- [Physical Intelligence openpi / π0.5](https://github.com/Physical-Intelligence/openpi)

## Notes

This repository is an engineering archive of the competition workflow rather than a plug-and-play deployment package. Real-hardware deployment depends on the specific A1Z calibration, CAN interface, camera enumeration, CloudRobo credential bundle and model-service configuration used on site.
