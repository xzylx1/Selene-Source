# Selene Code Wiki

> 版本：1.6.8+2158  
> 最后更新：2026-10-05

---

## 目录

1. [项目概述](#1-项目概述)
2. [技术栈](#2-技术栈)
3. [整体架构](#3-整体架构)
4. [目录结构](#4-目录结构)
5. [模块详解](#5-模块详解)
   - [5.1 数据模型层 (models)](#51-数据模型层-models)
   - [5.2 服务层 (services)](#52-服务层-services)
   - [5.3 页面层 (screens)](#53-页面层-screens)
   - [5.4 组件层 (widgets)](#54-组件层-widgets)
   - [5.5 工具层 (utils)](#55-工具层-utils)
6. [关键类与函数说明](#6-关键类与函数说明)
7. [依赖关系](#7-依赖关系)
8. [核心数据流](#8-核心数据流)
9. [运行与构建](#9-运行与构建)
10. [配置说明](#10-配置说明)

---

## 1. 项目概述

**Selene** 是一款基于 [MoonTV](https://github.com/MoonTechLab/Selene) 的跨平台视频播放器，使用 Flutter 框架开发。它聚合了多个视频搜索源，提供影视、动漫、综艺、电视剧的搜索与播放能力，同时集成了直播电视、Bangumi 番剧放送表、豆瓣推荐等功能。

### 核心特性

- **双模式运行**：
  - **服务器模式**：登录 MoonTV 后端服务器，由服务器提供搜索源、直播源、收藏、播放记录等数据。
  - **本地模式**：通过订阅链接（Base58 编码的 JSON）获取搜索源与直播源，数据存储在本地 SharedPreferences 中。
- **多源聚合搜索**：并发请求多个视频 API 源，支持搜索建议、增量结果流（SSE）、聚合去重视图。
- **视频播放**：基于 `media_kit` 的跨平台播放器，支持 m3u8 流解析、源测速、DLNA 投屏、画中画（PiP）。
- **直播电视**：解析 M3U 播放列表，支持 EPG 节目单、频道分组、频道收藏。
- **Bangumi 新番**：调用 `bgm.tv` 日历接口，按星期展示每日放送。
- **豆瓣推荐**：抓取豆瓣电影/电视剧/综艺/动漫的推荐数据，支持多维度筛选。
- **用户数据同步**：播放记录、收藏夹、搜索历史在服务器模式下与后端同步，本地模式下持久化存储。
- **跨平台**：支持 Android、iOS、Windows、macOS、Linux、Web。

---

## 2. 技术栈

| 分类 | 技术 | 说明 |
|------|------|------|
| 框架 | Flutter (Dart SDK >=3.4.3 <4.0.0) | 跨平台 UI 框架 |
| 状态管理 | Provider (`ChangeNotifier`) | 轻量级状态管理，主要用于主题 |
| 网络请求 | `http` / `dio` | http 用于通用 API，dio 用于 m3u8 解析测速 |
| 视频播放 | `media_kit` + `media_kit_video` + `media_kit_libs_video` | 跨平台媒体播放引擎 |
| 本地存储 | `shared_preferences` | 键值对持久化 |
| 图片缓存 | `cached_network_image` | 网络图片缓存 |
| DLNA 投屏 | `dlna_dart` | DLNA 协议实现 |
| 路径获取 | `path_provider` | 获取应用文档目录 |
| 包信息 | `package_info_plus` | 获取当前版本号 |
| 窗口管理 | `bitsdojo_window` (Windows) / `macos_window_utils` (macOS) | 桌面端窗口定制 |
| 编码 | `bs58check` | Base58 订阅内容解码 |
| XML 解析 | `xml` | EPG XML 解析 |
| 编码转换 | `gbk_codec` | M3U 列表 GBK 编码处理 |
| 国际化 | `flutter_localizations` | 本地化支持 |
| 图标 | `lucide_icons_flutter` / `cupertino_icons` | 图标库 |

---

## 3. 整体架构

Selene 采用典型的 Flutter 分层架构，整体分为 **数据模型层、服务层、页面层、组件层、工具层** 五层。

```
┌─────────────────────────────────────────────────────────┐
│                     页面层 (screens)                      │
│  LoginScreen │ HomeScreen │ SearchScreen │ PlayerScreen  │
│  MovieScreen │ TvScreen │ AnimeScreen │ ShowScreen       │
│  LiveScreen  │ LivePlayerScreen                          │
└──────────────────────┬──────────────────────────────────┘
                       │ 调用
┌──────────────────────▼──────────────────────────────────┐
│                    组件层 (widgets)                       │
│  MainLayout │ VideoPlayerWidget │ DLNAPlayer              │
│  VideoCard │ 各类 Section/Grid │ Player*Panel             │
└──────────────────────┬──────────────────────────────────┘
                       │ 调用
┌──────────────────────▼──────────────────────────────────┐
│                    服务层 (services)                      │
│  ApiService │ SearchService │ SSESearchService            │
│  DownstreamService │ DoubanService │ BangumiService       │
│  LiveService │ M3U8Service │ PageCacheService             │
│  UserDataService │ LocalModeStorageService                │
│  SubscriptionService │ VersionService │ ThemeService      │
└──────────────────────┬──────────────────────────────────┘
                       │ 使用
┌──────────────────────▼──────────────────────────────────┐
│                   数据模型层 (models)                     │
│  SearchResult │ SearchResource │ VideoInfo │ PlayRecord   │
│  FavoriteItem │ LiveChannel │ LiveSource │ EpgProgram     │
│  Bangumi* │ Douban* │ AggregatedSearchResult              │
└─────────────────────────────────────────────────────────┘
                       ▲
┌──────────────────────┴──────────────────────────────────┐
│                    工具层 (utils)                         │
│  DeviceUtils │ FontUtils │ image_url                      │
└─────────────────────────────────────────────────────────┘
```

### 设计模式

- **单例模式**：`DoubanCacheService`、`PageCacheService`、`LocalSearchCacheService` 均采用单例。
- **接口抽象**：`data_operation_interface.dart` 定义了 `PlayRecordOperationInterface`、`FavoriteOperationInterface`、`SearchRecordOperationInterface` 三个抽象接口，由 `PageCacheService` 统一实现，屏蔽服务器/本地模式差异。
- **策略模式**：图片源切换（`getImageUrl`）根据用户配置选择不同的 CDN 域名替换策略。
- **观察者模式**：`SSESearchService` 通过 `StreamController` 向外推送增量搜索结果、进度、错误事件。

---

## 4. 目录结构

```
/workspace
├── android/              # Android 平台原生工程
├── ios/                  # iOS 平台原生工程
├── linux/                # Linux 平台原生工程
├── macos/                # macOS 平台原生工程
├── windows/              # Windows 平台原生工程
├── web/                  # Web 平台资源
├── lib/                  # Dart 源代码（核心）
│   ├── main.dart         # 应用入口
│   ├── models/           # 数据模型
│   ├── services/         # 业务服务
│   ├── screens/          # 页面
│   ├── widgets/          # 可复用组件
│   └── utils/            # 工具函数
├── test/                 # 测试脚本（Shell）
├── pubspec.yaml          # 依赖与配置
├── build.sh              # 多平台构建脚本
└── analysis_options.yaml # 静态分析配置
```

---

## 5. 模块详解

### 5.1 数据模型层 (models)

所有模型均位于 `lib/models/`，负责数据结构定义与 JSON 序列化/反序列化。

| 文件 | 主要类 | 说明 |
|------|--------|------|
| `search_result.dart` | `SearchResult`, `SearchEvent` 系列 | 搜索结果核心模型 + WebSocket 搜索事件（start/sourceResult/sourceError/complete） |
| `search_resource.dart` | `SearchResource` | 视频搜索源配置（key、name、api、detail、from、disabled） |
| `search_suggestion.dart` | `SearchSuggestion` | 搜索建议 |
| `aggregated_search_result.dart` | `AggregatedSearchResult` | 聚合搜索结果（按标题+年份+类型去重，合并多源） |
| `video_info.dart` | `VideoInfo` | 视频卡片展示模型，可由 `PlayRecord`/`SearchResult`/`DoubanRecommendItem` 转换而来 |
| `play_record.dart` | `PlayRecord` | 播放记录（含播放进度、总时长、保存时间） |
| `favorite_item.dart` | `FavoriteItem` | 收藏项 |
| `live_source.dart` | `LiveSource` | 直播源（key、name、url、ua、epg、from） |
| `live_channel.dart` | `LiveChannel`, `LiveChannelGroup` | 直播频道与分组 |
| `epg_program.dart` | `EpgProgram`, `EpgData` | EPG 节目单数据 |
| `m3u_content.dart` | `M3uContent` | M3U 解析结果（tvgUrl + channels） |
| `bangumi.dart` | `BangumiItem`, `BangumiRating`, `BangumiCalendarResponse` 等 | Bangumi 番剧数据 |
| `douban_movie.dart` | `DoubanRecommendItem`, `DoubanMovieDetails` | 豆瓣推荐与电影详情 |

#### 关键模型关系

- `SearchResult` → `VideoInfo`（通过 `toVideoInfo()`）
- `PlayRecord` → `VideoInfo`（通过 `VideoInfo.fromPlayRecord()`）
- `DoubanRecommendItem` → `VideoInfo`（通过 `toVideoInfo()`）
- `AggregatedSearchResult` → `VideoInfo`（通过 `toVideoInfo()`）

`VideoInfo` 是 UI 层统一的展示模型，屏蔽了不同数据源（搜索、播放记录、收藏、豆瓣、Bangumi）的差异。

---

### 5.2 服务层 (services)

服务层位于 `lib/services/`，封装了所有业务逻辑、网络请求、缓存与存储。

#### 通用基础服务

| 服务 | 职责 |
|------|------|
| `ApiService` | 通用 HTTP 请求封装（GET/POST/PUT/DELETE/上传），统一处理认证 Cookie、401 跳转、响应解析；同时提供登录、搜索资源、直播源、收藏、播放记录等具体 API。 |
| `UserDataService` | 基于 `SharedPreferences` 存储用户登录信息（服务器地址、用户名、密码、Cookie）、豆瓣数据源/图片源配置、本地模式开关。 |
| `ThemeService` | `ChangeNotifier` 实现，管理亮/暗/系统主题，提供 `lightTheme`/`darkTheme`，macOS 下同步窗口外观。 |
| `VersionService` | 通过 GitHub Releases API 检查版本更新，支持版本号比较、每日提示频率限制、忽略指定版本。 |

#### 搜索相关服务

| 服务 | 职责 |
|------|------|
| `SearchService` | 搜索入口服务。提供 `searchRecommand`（搜索建议，仅搜第一个源）、`searchSync`（同步并发搜索所有源）、`getDetailSync`（获取视频详情，解析 m3u8 播放列表）。服务器模式使用内存缓存，本地模式走本地存储。 |
| `SSESearchService` | 流式搜索服务。通过 `StreamController` 提供 `incrementalResultsStream`、`progressStream`、`errorStream`，实现搜索结果增量推送与进度展示。支持本地并发搜索。 |
| `DownstreamService` | 下游搜索服务。直接调用单个 `SearchResource` 的 API（`?ac=videolist&wd=`），支持分页拉取（最多 5 页），通过 `ContentFilterService` 过滤不良内容，并使用 `LocalSearchCacheService` 缓存分页结果。 |
| `ContentFilterService` | 内容过滤服务，维护黄色关键词列表，对搜索结果的 `typeName` 进行过滤。 |

#### 内容推荐服务

| 服务 | 职责 |
|------|------|
| `DoubanService` | 豆瓣数据服务。请求豆瓣推荐接口，支持电影/电视剧/综艺/动漫多维度筛选。使用随机子域名规避限流，通过 `DoubanCacheService` 做磁盘+内存缓存。 |
| `BangumiService` | Bangumi 番剧服务。调用 `https://api.bgm.tv/calendar` 获取每日放送表，缓存 1 天。 |

#### 直播服务

| 服务 | 职责 |
|------|------|
| `LiveService` | 直播服务。获取直播源列表、频道列表（M3U 解析）、EPG 节目单。采用乐观缓存策略（过期先返回旧数据，后台异步刷新），缓存时长 2 小时。支持 GBK 编码的 M3U 解析。 |
| `M3U8Service` | M3U8 解析与测速服务。基于 `dio` 获取 m3u8 片段列表，并发测量分辨率、下载速度、延迟，用于播放源测速排序。 |

#### 缓存服务

| 服务 | 职责 |
|------|------|
| `DoubanCacheService` | 豆瓣数据磁盘缓存（单例）。在应用文档目录下 `douban_cache/` 存储 JSON 文件，支持 TTL 过期、定期清理。被 `DoubanService` 和 `BangumiService` 复用。 |
| `PageCacheService` | 页面级内存缓存（单例）。实现了播放记录、收藏、搜索历史三个操作接口，优先返回缓存，缓存未命中走 API 并回填。服务器/本地模式自动切换。 |
| `LocalSearchCacheService` | 本地搜索分页缓存（单例）。按 `sourceKey::query::page` 为键缓存搜索结果，TTL 10 分钟，最大 1000 条，定期惰性清理。 |

#### 存储与订阅服务

| 服务 | 职责 |
|------|------|
| `LocalModeStorageService` | 本地模式存储。持久化订阅 URL、搜索源列表、直播源列表、播放记录、收藏夹、搜索历史到 `SharedPreferences`。 |
| `SubscriptionService` | 订阅内容解析。将 Base58 编码的订阅内容解码为 JSON，解析出 `api_site`（搜索源）和 `lives`（直播源）。 |

#### 数据操作接口

`data_operation_interface.dart` 定义了三个抽象接口，统一服务器/本地模式的数据操作：

- `PlayRecordOperationInterface`：播放记录增删改查
- `FavoriteOperationInterface`：收藏夹增删查
- `SearchRecordOperationInterface`：搜索历史增删查

由 `PageCacheService` 统一实现。

---

### 5.3 页面层 (screens)

| 页面 | 说明 |
|------|------|
| `LoginScreen` | 登录页。支持服务器模式（地址+用户名+密码）和本地模式（订阅链接）。连续点击 Logo 10 次可切换本地模式。登录成功后保存用户数据并跳转首页。 |
| `HomeScreen` | 首页。包含顶部分类 Tab（首页/电影/电视剧/动漫/综艺）和底部导航（首页/搜索/直播/我的）。展示「继续观看」「热门电影」「热门电视剧」「热门综艺」「新番放送」等 Section，下拉刷新播放记录和收藏缓存，延迟 3 秒检查应用更新。 |
| `SearchScreen` | 搜索页。使用 `SSESearchService` 进行流式搜索，支持搜索历史、搜索建议、源/年份筛选、年份排序、聚合视图（按标题+年份去重合并多源）。 |
| `PlayerScreen` | 视频播放页。核心播放页面，负责搜索播放源、测速选优、调用 `VideoPlayerWidget` 播放、展示豆瓣详情、分集/多源切换面板、收藏、DLNA 投屏。 |
| `LivePlayerScreen` | 直播播放页。播放直播频道流。 |
| `MovieScreen` | 电影页。基于豆瓣推荐数据，支持热门/最新/豆瓣高分/冷门佳片等分类，以及类型、地区、年份等多维度筛选。 |
| `TvScreen` | 电视剧页。类似电影页，按国产/欧美/日韩等分类。 |
| `AnimeScreen` | 动漫页。包含「每日放送」（Bangumi 日历）、「番剧」「剧场版」三个模式，番剧模式下支持按类型筛选。 |
| `ShowScreen` | 综艺页。按国内/国外分类，支持类型筛选。 |
| `LiveScreen` | 直播页。展示直播源切换、频道分组、EPG 节目单，支持频道收藏。 |

---

### 5.4 组件层 (widgets)

#### 布局与导航

| 组件 | 说明 |
|------|------|
| `MainLayout` | 主布局骨架。包含顶部搜索栏、用户菜单、主题切换、底部导航栏，Windows 下集成自定义标题栏。 |
| `WindowsTitleBar` | Windows 自定义标题栏（拖动、最小化/最大化/关闭）。 |
| `TopTabSwitcher` / `CapsuleTabSwitcher` / `SimpleTabSwitcher` | 多种 Tab 切换组件。 |

#### 播放器组件

| 组件 | 说明 |
|------|------|
| `VideoPlayerWidget` | 基于 `media_kit` 的视频播放器。封装 `Player` + `VideoController`，提供 `VideoPlayerWidgetController` 供外部控制（切换源、seek、获取位置）。支持移动端与 PC 端两套控制条、画中画、全屏。 |
| `VideoPlayerSurface` | 播放器表面枚举（mobile/pc）。 |
| `MobilePlayerControls` / `PCPlayerControls` | 移动端/PC 端播放控制条。 |
| `DLNAPlayer` | DLNA 投屏播放器，基于 `dlna_dart`，支持播放/暂停/seek、进度回调、切换设备。 |
| `DLNADeviceDialog` | DLNA 设备发现与选择对话框。 |
| `DLNAPlayerControls` | DLNA 播放控制条。 |

#### 列表与卡片

| 组件 | 说明 |
|------|------|
| `VideoCard` | 通用视频卡片，展示封面、标题、评分、播放进度条。 |
| `VideoMenuBottomSheet` | 视频卡片长按/点击弹出的操作菜单（播放、收藏、查看详情等）。 |
| `ContinueWatchingSection` | 继续观看横向滚动列表。 |
| `HotMoviesSection` / `HotTvSection` / `HotShowSection` | 热门影视横向列表。 |
| `BangumiSection` / `BangumiGrid` | 新番放送区域。 |
| `RecommendationSection` | 推荐列表。 |
| `DoubanMoviesGrid` | 豆瓣影片网格。 |
| `FavoritesGrid` | 收藏夹网格。 |
| `HistoryGrid` | 播放历史网格。 |
| `SearchResultsGrid` / `SearchResultAggGrid` | 搜索结果网格（普通/聚合视图）。 |

#### 播放器面板

| 组件 | 说明 |
|------|------|
| `PlayerDetailsPanel` | 播放页右侧/底部详情面板（豆瓣简介、演职员等）。 |
| `PlayerEpisodesPanel` | 分集列表面板。 |
| `PlayerSourcesPanel` | 多播放源切换面板（含测速结果）。 |

#### 通用组件

| 组件 | 说明 |
|------|------|
| `CustomRefreshIndicator` | 自定义下拉刷新。 |
| `CustomSwitch` | 自定义开关。 |
| `FilterOptionsSelector` / `FilterPillHover` | 筛选选项选择器。 |
| `FullscreenImageViewer` | 全屏图片查看器。 |
| `ShimmerEffect` / `PulsingDotsIndicator` | 加载动画。 |
| `SwitchLoadingOverlay` | 切换源/集数时的加载蒙版。 |
| `UpdateDialog` | 应用更新提示弹窗。 |
| `UserMenu` | 用户菜单（退出登录、数据源设置等）。 |

---

### 5.5 工具层 (utils)

| 工具 | 说明 |
|------|------|
| `DeviceUtils` | 设备判断工具。判断平板/PC、平板竖屏、动态计算网格列数、横向列表可见卡片数、直播频道列数。 |
| `FontUtils` | 字体工具。Windows 下使用微软雅黑，其他平台使用 Google Fonts（Poppins / Source Code Pro）。 |
| `image_url` | 图片地址处理。根据豆瓣图片源配置（直连/腾讯 CDN/阿里 CDN/官方 CDN）替换域名，并返回防盗链请求头。 |

---

## 6. 关键类与函数说明

### 6.1 应用入口 (`main.dart`)

```dart
void main() async
```
- 初始化 `MediaKit`（PC 端播放器引擎）
- macOS 下配置透明标题栏与全屏内容视图
- 初始化 `DoubanCacheService` 并启动定期清理
- `runApp(SeleneApp())` 启动应用
- Windows 下通过 `bitsdojo_window` 设置窗口最小尺寸（1024×600）

`SeleneApp` 通过 `ChangeNotifierProvider<ThemeService>` 提供主题，`AppWrapper` 检查登录状态：
- 本地模式：刷新订阅内容 → 进入 `HomeScreen`
- 服务器模式：调用 `ApiService.autoLogin()` → 成功进首页，失败进 `LoginScreen`

### 6.2 `ApiService`

| 方法 | 说明 |
|------|------|
| `get<T>` / `post<T>` / `put<T>` / `delete<T>` | 通用 REST 请求，30 秒超时，自动附加 Cookie，401 时清除数据并跳转登录页。 |
| `uploadFile<T>` | multipart 文件上传。 |
| `autoLogin()` | 服务器模式自动登录，POST `/api/login`，解析并保存 Cookie。 |
| `getSearchResources()` | GET `/api/search/resources`，返回搜索源列表。 |
| `getLiveSources()` | GET `/api/live/sources`，返回直播源列表。 |
| `getFavorites(context)` | GET `/api/favorites`，返回收藏列表（按 saveTime 降序）。 |
| `fetchSourceDetail(source, id)` | GET `/api/detail?source=&id=`，获取视频详情。 |
| `fetchSourcesData(query)` | GET `/api/search?q=`，服务器代理搜索。 |

### 6.3 `SearchService`

| 方法 | 说明 |
|------|------|
| `searchRecommand(query)` | 搜索建议，仅请求第一个源，5 秒超时，返回标题去重列表。 |
| `searchSync(query)` | 同步并发搜索所有启用的源，每个源 20 秒超时，按源顺序合并结果。 |
| `getDetailSync(source, id)` | 获取视频详情，解析 `vod_play_url` 中的 m3u8 链接（`$$$` 分源，`#` 分集，`$` 分隔标题与链接）。支持特殊源（通过 HTML 页面正则解析 m3u8）。 |

### 6.4 `SSESearchService`

流式搜索，对外暴露三个 Stream：
- `incrementalResultsStream` — 增量搜索结果
- `progressStream` — `SearchProgress`（总源数、已完成源数、当前源、是否完成）
- `errorStream` — 错误信息

核心方法 `localSearch(query)` 并发调用所有源，逐个推送结果与进度。

### 6.5 `PageCacheService`（单例）

实现三个数据操作接口，核心逻辑：
1. 判断本地/服务器模式
2. 优先返回内存缓存
3. 缓存未命中 → 调用 API 或本地存储 → 回填缓存
4. 提供 `refresh*` 方法强制刷新

### 6.6 `DoubanService`

- `_getUniqueOrigin()`：生成随机子域名 Origin，规避豆瓣统一限流
- 支持 `DoubanRecommendsParams`（kind/category/format/region/year/platform/sort/label/page）多维度筛选
- 通过 `DoubanCacheService` 缓存，减少网络请求

### 6.7 `LiveService`

- `getLiveSources()` / `getLiveChannels(sourceKey)` / `getEpg(sourceKey, tvgId)`
- 乐观缓存：缓存未过期直接返回；已过期先返回旧数据，后台异步刷新
- M3U 解析支持 `#EXTM3U`、`#EXTINF`、`#EXTGRP`、`#EXTVLCOPT` 标签，支持 GBK 编码

### 6.8 `SubscriptionService`

`parseSubscriptionContent(content)`：
1. Base58 解码内容
2. UTF-8 解码为 JSON 字符串
3. 解析 `api_site` → `List<SearchResource>`
4. 解析 `lives` → `List<LiveSource>`

---

## 7. 依赖关系

### 7.1 服务层内部依赖

```
ApiService ──────────────► UserDataService (读取服务器地址/Cookie)
                         ► LoginScreen (401 跳转)

SearchService ──────────► ApiService (服务器模式获取搜索源)
                         ► LocalModeStorageService (本地模式)
                         ► DownstreamService (实际搜索调用)
                         ► UserDataService (判断模式)

SSESearchService ───────► ApiService / LocalModeStorageService (搜索源)
                         ► DownstreamService (单源搜索)

DownstreamService ──────► ContentFilterService (内容过滤)
                         ► LocalSearchCacheService (分页缓存)

DoubanService ──────────► DoubanCacheService (磁盘缓存)
                         ► UserDataService (数据源配置)

BangumiService ─────────► DoubanCacheService (复用缓存)

LiveService ────────────► ApiService / LocalModeStorageService
                         ► gbkk_codec (M3U 编码)
                         ► xml (EPG 解析)

PageCacheService ───────► ApiService (服务器模式 API)
                         ► LocalModeStorageService (本地模式)
                         ► UserDataService (模式判断)

SubscriptionService ────► bs58check (Base58 解码)
                         ► SearchResource / LiveSource 模型
```

### 7.2 页面 → 服务依赖

```
LoginScreen ──► UserDataService, LocalModeStorageService, SubscriptionService
HomeScreen ───► PageCacheService, VersionService
SearchScreen ─► SSESearchService, PageCacheService, ThemeService
PlayerScreen ─► ApiService, SearchService, DoubanService, M3U8Service,
                UserDataService, PageCacheService
Movie/Tv/Anime/ShowScreen ──► DoubanService, BangumiService
LiveScreen ────► LiveService
```

### 7.3 播放器组件依赖

```
PlayerScreen ──► VideoPlayerWidget ──► media_kit
             ──► DLNAPlayer ──► dlna_dart
             ──► M3U8Service (测速)
```

---

## 8. 核心数据流

### 8.1 启动流程

```
main()
  ├─ MediaKit.ensureInitialized()
  ├─ macOS 窗口配置
  ├─ DoubanCacheService.init() + startPeriodicCleanup()
  └─ runApp(SeleneApp)
       └─ AppWrapper._checkLoginStatus()
            ├─ isLocalMode?
            │    ├─ 是 → 刷新订阅 → HomeScreen
            │    └─ 否 → hasAutoLoginData?
            │              ├─ 否 → LoginScreen
            │              └─ 是 → ApiService.autoLogin()
            │                        ├─ 成功 → HomeScreen
            │                        └─ 失败 → LoginScreen
```

### 8.2 搜索播放流程

```
SearchScreen
  └─ SSESearchService.localSearch(query)
       ├─ 获取搜索源（ApiService / LocalModeStorageService）
       ├─ 并发 DownstreamService.searchFromApi(resource, query)
       │    ├─ 请求 ?ac=videolist&wd=query（最多 5 页）
       │    ├─ ContentFilterService 过滤
       │    └─ LocalSearchCacheService 缓存
       └─ 推送增量结果到 incrementalResultsStream

用户点击搜索结果
  └─ PlayerScreen
       ├─ SearchService.getDetailSync(source, id) 解析播放列表
       ├─ 并发 M3U8Service.getStreamInfo 测速各源
       ├─ VideoPlayerWidget 播放最优源
       └─ PageCacheService.savePlayRecord 保存播放记录
```

### 8.3 本地模式数据流程

```
LoginScreen 输入订阅 URL
  └─ http.get(subscriptionUrl)
       └─ SubscriptionService.parseSubscriptionContent(Base58 内容)
            ├─ searchResources → LocalModeStorageService.saveSearchSources()
            └─ liveSources → LocalModeStorageService.saveLiveSources()

搜索时：SearchService → LocalModeStorageService.getSearchSources() → DownstreamService
直播时：LiveService → LocalModeStorageService.getLiveSources() → M3U 解析
```

---

## 9. 运行与构建

### 9.1 环境要求

- Flutter SDK（Dart >=3.4.3 <4.0.0）
- 各平台原生工具链（Android Studio / Xcode / Visual Studio / Linux 工具链）

### 9.2 开发运行

```bash
# 安装依赖
flutter pub get

# 运行（默认设备）
flutter run

# 指定平台运行
flutter run -d windows
flutter run -d macos
flutter run -d chrome
```

### 9.3 构建

项目提供 `build.sh` 脚本，支持多平台并行/顺序构建。

```bash
# 全平台构建（Android + iOS + macOS ARM64 + x86_64，并行）
./build.sh

# 仅构建 Android
./build.sh --android-only

# 仅构建 iOS
./build.sh --ios-only

# 仅构建 macOS（ARM64 + x86_64）
./build.sh --macos-only

# 仅构建 macOS ARM64
./build.sh --macos-arm64-only

# 构建所有 Apple 平台（iOS + macOS）
./build.sh --apple-only

# 顺序构建（默认并行）
./build.sh --sequential

# 查看帮助
./build.sh --help
```

#### 构建产物

构建产物输出到 `dist/` 目录：

| 平台 | 产物 |
|------|------|
| Android | `selene-{version}-armv8.apk`、`selene-{version}-armv7a.apk`（混淆 + 符号分离） |
| iOS | `selene-{version}.ipa`（无签名） |
| macOS ARM64 | `selene-{version}-macos-arm64.dmg` |
| macOS x86_64 | `selene-{version}-macos-x86_64.dmg` |

#### 手动构建

```bash
# Android APK
flutter build apk --release --split-per-abi

# Windows
flutter build windows --release

# macOS
flutter build macos --release

# iOS（无签名）
flutter build ios --release --no-codesign

# Web
flutter build web --release
```

### 9.4 应用图标

使用 `flutter_launcher_icons` 生成各平台图标，源文件为根目录 `logo.png`：

```bash
flutter pub run flutter_launcher_icons
```

---

## 10. 配置说明

### 10.1 pubspec.yaml 关键配置

- `version: 1.6.8+2158` — 版本号 + 构建号
- `environment.sdk: '>=3.4.3 <4.0.0'`
- `flutter.uses-material-design: true`
- `flutter.generate: true` — 启用本地化生成

### 10.2 平台特定配置

| 平台 | 配置项 |
|------|--------|
| Android | `minSdkVersion` 由 `flutter_launcher_icons` 配置为 21；`network_security_config.xml` 配置网络安全策略 |
| iOS | `Info.plist` 配置；支持无签名构建 |
| Windows | 窗口最小尺寸 1024×600；自定义标题栏 |
| macOS | 透明标题栏、全屏内容视图、隐藏标题 |

### 10.3 后端 API 约定（服务器模式）

所有 API 基于用户配置的服务器地址，自动附加 Cookie 认证：

| Endpoint | 方法 | 说明 |
|----------|------|------|
| `/api/login` | POST | 登录，返回 Set-Cookie |
| `/api/search/resources` | GET | 获取搜索源列表 |
| `/api/live/sources` | GET | 获取直播源列表 |
| `/api/search?q=` | GET | 服务器代理搜索 |
| `/api/detail?source=&id=` | GET | 获取视频详情 |
| `/api/favorites` | GET | 获取收藏夹 |
| `/api/playrecords` | GET | 获取播放记录 |
| `/api/searchhistory` | GET | 获取搜索历史 |

### 10.4 订阅内容格式（本地模式）

订阅 URL 返回 Base58 编码的 JSON，结构如下：

```json
{
  "api_site": {
    "source_key": {
      "key": "source_key",
      "name": "源名称",
      "api": "https://api.example.com/api.php",
      "detail": "",
      "from": "自定义",
      "disabled": false
    }
  },
  "lives": {
    "live_key": {
      "key": "live_key",
      "name": "直播源名称",
      "url": "https://example.com/playlist.m3u",
      "ua": "",
      "epg": "",
      "from": "自定义",
      "disabled": false
    }
  }
}
```

### 10.5 视频源 API 约定

搜索源 API 基于通用的 `?ac=videolist` 协议（类似苹果 CMS）：

- 搜索：`{api}?ac=videolist&wd={query}&pg={page}`
- 详情：`{api}?ac=videolist&ids={id}`
- 播放地址格式：`vod_play_url` 字段，`$$$` 分隔多个源，`#` 分隔集数，`$` 分隔标题与链接

---

## 附录：文件清单速查

### models (12 个文件)
`aggregated_search_result.dart`, `bangumi.dart`, `douban_movie.dart`, `epg_program.dart`, `favorite_item.dart`, `live_channel.dart`, `live_source.dart`, `m3u_content.dart`, `play_record.dart`, `search_resource.dart`, `search_result.dart`, `search_suggestion.dart`, `video_info.dart`

### services (17 个文件)
`api_service.dart`, `bangumi_service.dart`, `content_filter_service.dart`, `data_operation_interface.dart`, `douban_cache_service.dart`, `douban_service.dart`, `downstream_service.dart`, `live_service.dart`, `local_mode_storage_service.dart`, `local_search_cache_service.dart`, `m3u8_service.dart`, `page_cache_service.dart`, `search_service.dart`, `sse_search_service.dart`, `subscription_service.dart`, `theme_service.dart`, `user_data_service.dart`, `version_service.dart`

### screens (9 个文件)
`anime_screen.dart`, `home_screen.dart`, `live_player_screen.dart`, `live_screen.dart`, `login_screen.dart`, `movie_screen.dart`, `player_screen.dart`, `search_screen.dart`, `show_screen.dart`, `tv_screen.dart`

### widgets (30+ 个文件)
涵盖布局、播放器、列表卡片、面板、通用组件五大类（详见 5.4 节）

### utils (3 个文件)
`device_utils.dart`, `font_utils.dart`, `image_url.dart`
