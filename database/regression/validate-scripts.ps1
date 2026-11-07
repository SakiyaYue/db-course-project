#requires -Version 7.2
param([string]$ScriptDomPath)
$ErrorActionPreference='Stop'
$taskRoot=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path
if (-not $ScriptDomPath) {
    $taskCandidates=@(
        'C:\Program Files\Azure Data Studio\resources\app\extensions\mssql\sqltoolsservice\Windows\4.10.2.1\Microsoft.SqlServer.TransactSql.ScriptDom.dll'
    )
    $ScriptDomPath=$taskCandidates | Where-Object {Test-Path -LiteralPath $_} | Select-Object -First 1
}
if (-not $ScriptDomPath) {throw 'Pass -ScriptDomPath for an installed Microsoft T-SQL ScriptDom assembly.'}
Add-Type -Path $ScriptDomPath
if (-not ('TeabarEmbeddedSqlVisitor' -as [type])) {
    $taskReferenceDirectory=Join-Path $PSHOME 'ref'
    $taskReferences=@($ScriptDomPath)+@(Get-ChildItem -LiteralPath $taskReferenceDirectory -Filter '*.dll' | ForEach-Object FullName)
    Add-Type -ReferencedAssemblies $taskReferences -CompilerOptions '/nowarn:1701' -TypeDefinition @'
using System;
using System.Collections.Generic;
using Microsoft.SqlServer.TransactSql.ScriptDom;
public sealed class TeabarEmbeddedSql {
    public string Sql; public int Line;
    public TeabarEmbeddedSql(string sql, int line) { Sql=sql; Line=line; }
}
public sealed class TeabarEmbeddedSqlVisitor : TSqlFragmentVisitor {
    public readonly List<TeabarEmbeddedSql> Found = new List<TeabarEmbeddedSql>();
    public override void Visit(InsertSpecification node) {
        var source=node.InsertSource as ValuesInsertSource;
        if (source==null || !(node.Target is VariableTableReference)) return;
        for (int i=0;i<node.Columns.Count;i++) {
            var ids=node.Columns[i].MultiPartIdentifier.Identifiers;
            string name=ids[ids.Count-1].Value;
            if (name!="statement" && name!="setup" && name!="assertion" && name!="teardown") continue;
            foreach (var row in source.RowValues) {
                var value=row.ColumnValues[i] as StringLiteral;
                if (value!=null) Found.Add(new TeabarEmbeddedSql(value.Value,value.StartLine));
            }
        }
    }
    public override void Visit(ExecutableStringList node) {
        // Only complete literal EXEC batches; concatenated DDL needs runtime validation.
        if (node.Strings.Count!=1) return;
        var value=node.Strings[0] as StringLiteral;
        if (value!=null) Found.Add(new TeabarEmbeddedSql(value.Value,value.StartLine));
    }
    public override void Visit(DeclareVariableElement node) {
        var value=node.Value as StringLiteral;
        if ((node.VariableName.Value=="@fingerprint" || node.VariableName.Value=="@security_fingerprint") && value!=null)
            Found.Add(new TeabarEmbeddedSql(value.Value,value.StartLine));
    }
}
'@
}
$taskParserType=[Microsoft.SqlServer.TransactSql.ScriptDom.TSqlParser].Assembly.GetExportedTypes() |
    Where-Object Name -Match '^TSql\d+Parser$' | Sort-Object { [int]($_.Name -replace '\D','') } -Descending | Select-Object -First 1
$taskParser=[Activator]::CreateInstance($taskParserType,@($true))
$taskFiles=@(Get-ChildItem -LiteralPath (Join-Path $taskRoot 'database/migrations/v0.1-to-v1.0') -Recurse -Filter '*.sql')
$taskFiles+=@(Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.sql' | Where-Object Name -In @('regression.sql','regression-body.sql','legacy-constraint-tests.sql','legacy-role-tests.sql','v1.0-new-tests.sql','verify-rollback.sql','source-integrity.sql','key-query-compare.sql','v1.0-object-capture.sql','work-copy.sql','configure-web-access.sql'))
$taskFailures=0
$taskEmbeddedCount=0
$taskSeen=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
$taskQueue=New-Object 'System.Collections.Generic.Queue[object]'
foreach ($taskFile in $taskFiles) {
    $taskQueue.Enqueue(@{Label=$taskFile.Name;Sql=[IO.File]::ReadAllText($taskFile.FullName);Embedded=$false})
}
while ($taskQueue.Count) {
    $taskItem=$taskQueue.Dequeue()
    if ($taskItem.Embedded -and -not $taskSeen.Add($taskItem.Sql)) {continue}
    if ($taskItem.Embedded) {$taskEmbeddedCount++}
    $taskErrors=New-Object 'System.Collections.Generic.List[Microsoft.SqlServer.TransactSql.ScriptDom.ParseError]'
    $taskReader=New-Object IO.StringReader($taskItem.Sql)
    $taskFragment=$taskParser.Parse($taskReader,[ref]$taskErrors)
    $taskReader.Dispose()
    foreach ($taskError in $taskErrors) {
        Write-Output "$($taskItem.Label):$($taskError.Line):$($taskError.Column) $($taskError.Message)"
        $taskFailures++
    }
    if (-not $taskErrors.Count) {
        $taskVisitor=New-Object TeabarEmbeddedSqlVisitor
        $taskFragment.Accept($taskVisitor)
        foreach ($taskInner in $taskVisitor.Found) {
            $taskQueue.Enqueue(@{Label="$($taskItem.Label)/literal@$($taskInner.Line)";Sql=$taskInner.Sql;Embedded=$true})
        }
    }
}
Write-Output "Static parser: $($taskParserType.Name); files: $($taskFiles.Count); distinct embedded SQL batches: $taskEmbeddedCount; parse errors: $taskFailures. No SQL was executed."
if ($taskFailures) {exit 1}
