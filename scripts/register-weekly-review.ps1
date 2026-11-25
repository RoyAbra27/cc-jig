$bash = 'C:\Program Files\Git\bin\bash.exe'
$action = New-ScheduledTaskAction -Execute 'conhost.exe' -Argument "--headless `"$bash`" -lc ~/.claude/scripts/weekly-review.sh"
$trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Monday -At 9am
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 20)
Register-ScheduledTask -TaskName 'Claude setup review' -Action $action -Trigger $trigger -Settings $settings -Description 'Weekly read-only Claude Code setup review to Desktop' -Force | Out-Null
Get-ScheduledTask -TaskName 'Claude setup review' | Select-Object TaskName, State, @{n='Next';e={(Get-ScheduledTaskInfo $_).NextRunTime}}, @{n='Action';e={$_.Actions[0].Execute + ' ' + $_.Actions[0].Arguments}} | Format-List
