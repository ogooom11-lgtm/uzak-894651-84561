param(
    [string]$TaskName = "KIOM PC Agent"
)

$task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if (-not $task) {
    Write-Output "NOT_INSTALLED"
    exit 1
}

$info = Get-ScheduledTaskInfo -TaskName $TaskName -ErrorAction SilentlyContinue
[PSCustomObject]@{
    Status = "INSTALLED"
    TaskName = $TaskName
    State = $task.State.ToString()
    LastRunTime = $info.LastRunTime
    LastTaskResult = $info.LastTaskResult
} | ConvertTo-Json -Compress
