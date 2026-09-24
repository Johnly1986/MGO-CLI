# MGO CLI — 预编译二进制发布

本仓库**只承载 [MGO](https://github.com/Johnly1986/MGOServer) 三维切片引擎的预编译二进制 Release 产物**，不包含源码。

[![Platform](https://img.shields.io/badge/platform-Windows%20%7C%20Linux-lightgrey.svg)](#)
[![License: Apache-2.0](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)

## 下载

前往 [Releases](https://github.com/Johnly1986/MGO-CLI/releases)，选择最新版本，按平台取包：

| 平台 | 文件名 | 说明 |
|------|--------|------|
| Linux x64 | `MGO-<ver>-linux-x64.tar.gz` | 自包含：携带 PROJ/GDAL/Boost/OpenSceneGraph 依赖闭包 + OSG 插件目录 + `share/proj` 数据，解压即用，无需 apt 安装系统 GIS 库 |
| Windows x64 | `MGO-<ver>-win-x64.zip` | 自包含：携带 vcpkg 构建的 DLL 与 `osgPlugins-<version>`，解压即用 |

每个 Release 同时附带 `THIRD_PARTY_LICENSES.txt`（第三方组件许可清单）。

```bash
# Linux 示例
VER=v0.9.2
curl -L -o mgo.tar.gz \
  "https://github.com/Johnly1986/MGO-CLI/releases/download/${VER}/MGO-${VER#v}-linux-x64.tar.gz"
tar xzf mgo.tar.gz && cd MGO-${VER#v}-linux-x64
./MGOConsole --version
```

> 校验：包的 sha256 可在 [`MGOServer/package.json`](https://github.com/Johnly1986/MGOServer/blob/main/package.json) 的 `mgoEngine.downloads` 字段查到（安装器用它做完整性校验）。

## 命令行用法

```
mgo mesh     - 网格简化 + 坐标投影
mgo tiles    - FBX/OBJ -> 3D Tiles (b3dm + tileset.json)
mgo terrain  - GeoTIFF DEM -> Cesium Quantized-Mesh 地形瓦片
mgo image    - DOM 正射影像 -> TMS 图片瓦片
mgo geojson  - GeoJSON 坐标系转换
mgo osgb     - OSGB 倾斜摄影（大疆智图 / ContextCapture）-> 3D Tiles
```

完整参数说明、坐标系约定与示例见 [`MGOConsole --help`](#) 及
[MGOServer 文档](https://github.com/Johnly1986/MGOServer#readme)。

## 通过 Node.js 服务使用

若你需要 HTTP 接口 + CesiumJS 可视化，直接使用 [MGOServer](https://github.com/Johnly1986/MGOServer)：
它的安装脚本会自动从本仓库拉取匹配版本的引擎包并校验 sha256。

```bash
npm install @johnly1986/mgoserver   # postinstall 自动下载引擎
```

## 版本策略

- 版本号与本仓库 Release tag 一致（`v0.9.2` 形式）；tag 名含 `-` 者为预发布。
- 二进制由上游 CI 自动构建并发布，Linux / Windows 同 tag 同步产出。

## 许可与反馈

- 引擎以 Apache License 2.0 发布，见 [LICENSE](LICENSE)；随包第三方组件许可见附件 `THIRD_PARTY_LICENSES.txt`。
- 问题反馈、功能请求：https://github.com/Johnly1986/MGOServer/issues
