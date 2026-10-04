# 蜜雪冰城单门店数据库课程项目

面向单个门店的数据库课程项目，涵盖商品、原料库存、订单、会员、员工值班、规格和加料管理。数据库设计以 SQL Server 为目标，当前包含需求与设计文档、15 张表的关系模式及 ER 图，尚未提供 SQL 建表脚本或可运行的业务系统。

## 文件说明

| 文件 / 目录 | 内容 |
| --- | --- |
| [baseline.md](baseline.md) | 已确认的业务需求和设计原则 |
| [第二周关系模式与数据字典](docs/第二周关系模式与数据字典.md) | 表结构、字段、主外键、业务约束及待审查样例 |
| [ER图_修订版.png](ER图_修订版.png) | 当前设计对应的 ER 图 |
| `docs/er/` | ER 图的 SVG、DOT、预览图及结构化数据 `schema.json` |
| `scripts/绘制ER图.cjs` | 根据数据字典生成 ER 图的 Node.js 脚本 |
| `第一周任务讲解.docx` ～ `第四周任务讲解.docx` | 各周课程任务说明 |
| `ER图.png`、`ER图草图.jpg` | 早期设计参考 |

## 使用方法

下载或克隆仓库：

```sh
git clone https://github.com/SakiyaYue/db-course-project.git
cd db-course-project
```

建议先阅读 `baseline.md`，再查看数据字典和修订版 ER 图。Word 文档可用 Microsoft Word 或 WPS 打开；PNG 图片可直接查看，SVG 可用浏览器打开。

数据字典中标注“待确认”或“待审查”的选项、数值及样例不代表最终方案，后续实现以小组确认结果为准。

## 重新生成 ER 图（可选）

需要 Node.js 和 npm。以下命令在仓库根目录的 PowerShell 中执行：

```powershell
npm install --no-save --package-lock=false @viz-js/viz sharp
$env:ER_DEPENDENCY_PACKAGES = Join-Path (Get-Location).Path 'node_modules'
node .\scripts\绘制ER图.cjs
```

脚本读取 `docs/第二周关系模式与数据字典.md`，更新根目录的 `ER图_修订版.png` 及 `docs/er/` 下的生成文件。图中业务注释和联系定义也保存在脚本中，设计调整时应同步更新。渲染通过 `@viz-js/viz` 完成，无需单独安装 Graphviz；中文字体采用 Microsoft YaHei，建议在安装该字体的环境下生成。
