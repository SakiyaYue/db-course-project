# v1.0 迁移与回归证据

2026-11-07：**独立副本TeabarDB_Phase2_Work迁移成功，184/184回归通过。** 用户已授权仅在副本执行；冻结源TeabarDB操作前后指纹一致。当前结果重新运行原44+84项，并非只引用旧基线。

[实测结果与限制](../../../docs/phase2/06-normalization/迁移前后结果与已知限制.md)、[恢复步骤](../../../docs/phase2/06-normalization/迁移与恢复说明.md)及[执行摘要](execution-summary.json)提供结论、命令模式、退出码与哈希。[static-validation.txt](static-validation.txt)保留执行前静态记录，最新文件检查另见[static-validation-final.txt](static-validation-final.txt)。

## 实际执行证据

| 建议文件 | 内容 | 状态 |
| --- | --- | --- |
| [00-work-copy](00-work-copy.txt) | 来源、目标库、备份/文件路径、成功还原 | 通过，退出0 |
| [01-dry-run](01-dry-run.txt) / [02-verify](02-verify-dry-run.txt) | 默认回滚、旧对象与16表哈希恢复 | 均退出0 |
| [03-failure](03-injected-failure.txt) / [04-verify](04-verify-failure.txt) | 预期52809、事务状态0、旧定义及数据恢复 | 故障退出1（预期），核验退出0 |
| [05-commit](05-migration-commit.txt) | 17表81列19FK、原表哈希一致、COMMITTED_V1.0 | 通过，退出0 |
| [06-regression](06-regression.txt) | 184通过、0失败；17表与安全配置恢复 | 通过，退出0 |

补充：[冻结源操作前](00-source-before.txt)与[操作后](07-source-after.txt)报告完全相同；[08目标摘要](08-target-summary.txt)、[09关键查询对照](09-key-query-compare.txt)、[10完整对象与参数清单](10-target-objects.txt)均退出0。恢复备份路径已记录在00日志和执行摘要中，未纳入Git。

[attempts/](attempts/)保留修正前失败记录：过程头改写哈希、TVP内部约束计数、CREATE SCHEMA批次、禁止身份切换导致事务失效。最终成功日志不覆盖这些历史。错误消息中的本机主机名已脱敏，业务结果、错误号和退出码保持真实；不含密码、连接秘密或Web凭据哈希。
