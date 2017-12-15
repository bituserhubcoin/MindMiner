<#
MindMiner  Copyright (C) 2017  Oleg Samsonov aka Quake4/Quake3
https://github.com/Quake4/MindMiner
License GPL-3.0
#>

. .\Code\Out-Data.ps1

Out-Iam
Write-Host "Loading ..." -ForegroundColor Green

. .\Code\Include.ps1

# ctrl+c hook
[Console]::TreatControlCAsInput = $true

$BinLocation = [IO.Path]::Combine($(Get-Location), [Config]::BinLocation)
New-Item $BinLocation -ItemType Directory -Force | Out-Null
$BinScriptLocation = [scriptblock]::Create("Set-Location('$BinLocation')")
$DownloadJob = $null

# download prerequisites
Get-Prerequisites ([Config]::BinLocation)

# read and validate config
$Config = Get-Config

if (!$Config) { exit }

Clear-Host
Out-Header

$ActiveMiners = [Collections.Generic.Dictionary[string, MinerProcess]]::new()
[SummaryInfo] $Summary = [SummaryInfo]::new([Config]::RateTimeout)
[StatCache] $Statistics = [StatCache]::Read()
$Summary.TotalTime.Start()

# FastLoop - variable for benchmark or miner errors - very fast switching to other miner - without ask pools and miners
[bool] $FastLoop = $false 
# exit - var for exit
[bool] $exit = $false
# main loop
while ($true)
{
	if ($Summary.RateTime.IsRunning -eq $false -or $Summary.RateTime.Elapsed.TotalSeconds -ge [Config]::RateTimeout.TotalSeconds) {
		# Get-RateInfo
		$exit = Update-Miner ([Config]::BinLocation)
		if ($exit -eq $true) {
			$FastLoop = $true
		}
		$Summary.RateTime.Reset()
		$Summary.RateTime.Start()
	}

	if (!$FastLoop) {
		# read algorithm mapping
		$AllAlgos = <#[BaseConfig]::ReadOrCreate("Algo" + [BaseConfig]::Filename,#> @{
			# how to map algorithms
			Mapping = [ordered]@{
				"blakecoin" = "Blake"
				"blake256r8" = "Blake"
				"daggerhashimoto" = "Ethash"
				"lyra2rev2" = "Lyra2re2"
				"lyra2r2" = "Lyra2re2"
				"lyra2v2" = "Lyra2re2"
				"m7m" = "M7M"
				"neoscrypt" = "NeoScrypt"
				"sib" = "X11Gost"
				"x11gost" = "X11Gost"
				"x11evo" = "X11Evo"
				"phi1612" = "Phi"
				"timetravel10" = "Bitcore"
				"x13sm3" = "Hsr"
				"myriad-groestl" = "MyrGr"
				"myriadgroestl" = "MyrGr"
				"myr-gr" = "MyrGr"
				"jackpot" = "JHA"
			}
			# disable asic algorithms
			Disabled = @("sha256", "scrypt", "x11", "x13", "x14", "x15", "quark", "qubit")
		} #)

		Write-Host "Pool(s) request ..." -ForegroundColor Green
		$AllPools = Get-ChildItem "Pools" | Where-Object Extension -eq ".ps1" | ForEach-Object {
			Invoke-Expression "Pools\$($_.Name)"
		} | Where-Object { $_ -is [PoolInfo] -and $_.Profit -gt 0 }

		# find more profitable algo from all pools
		$AllPools = $AllPools | Select-Object Algorithm -Unique | ForEach-Object {
			$max = 0; $each = $null
			$AllPools | Where-Object Algorithm -eq $_.Algorithm | ForEach-Object {
				if ($max -lt $_.Profit) { $max = $_.Profit; $each = $_ }
			}
			if ($max -gt 0) { $each }
			Remove-Variable max
		}

		# check pool exists
		if (!$AllPools -or $AllPools.Length -eq 0) {
			Write-Host "No Pools!" -ForegroundColor Red
			Start-Sleep $Config.CheckTimeout
			continue
		}
		
		Write-Host "Miners request ..." -ForegroundColor Green
		$AllMiners = Get-ChildItem "Miners" | Where-Object Extension -eq ".ps1" | ForEach-Object {
			Invoke-Expression "Miners\$($_.Name)"
		}

		# filter by exists hardware
		$AllMiners = $AllMiners | Where-Object { [array]::IndexOf([Config]::ActiveTypes, ($_.Type -as [eMinerType])) -ge 0 }

		# download miner
		if (!(Get-Job -State Running) -and $DownloadJob) {
			Remove-Job -Name "Download"
			$DownloadJob = $null
		}
		$DownloadMiners = $AllMiners | Where-Object { !$_.Exists([Config]::BinLocation) } | Select-Object Path, URI -Unique | ForEach-Object { @{ Path = $_.Path; URI = $_.URI } }
		if ($DownloadMiners.Length -gt 0) {
			Write-Host "Download $($DownloadMiners.Length) miner(s) ... " -ForegroundColor Green
			if (!(Get-Job -State Running)) {
				Start-Job -Name "Download" -ArgumentList $DownloadMiners -FilePath ".\Code\Downloader.ps1" -InitializationScript $BinScriptLocation | Out-Null
				$DownloadJob = $true
			}
		}

		# check exists miners
		$AllMiners = $AllMiners | Where-Object { $_.Exists([Config]::BinLocation) }
		
		if ($AllMiners.Length -eq 0) {
			Write-Host "No Miners!" -ForegroundColor Red
			Start-Sleep $Config.CheckTimeout
			continue
		}

		# save speed active miners
		$ActiveMiners.Values | Where-Object { $_.State -eq [eState]::Running -and $_.Action -eq [eAction]::Normal } | ForEach-Object {
			$speed = $_.GetSpeed()
			if ($speed -gt 0) {
				$speed = $Statistics.SetValue($_.Miner.GetFilename(), $_.Miner.GetKey(), $speed, $Config.AverageHashSpeed, 0.25)
			}
			elseif ($speed -eq 0 -and $_.CurrentTime.Elapsed.TotalSeconds -ge $Config.LoopTimeout) {
				# no hasrate stop miner and move to nohashe state while not ended
				$_.Stop()
			}
		}
	}

	# stop benchmark by condition: timeout reached and has result or timeout more 5 and no result
	$ActiveMiners.Values | Where-Object { $_.State -eq [eState]::Running -and $_.Action -eq [eAction]::Benchmark } | ForEach-Object {
		$speed = $_.GetSpeed()
		if (($_.CurrentTime.Elapsed.TotalSeconds -ge $_.Miner.BenchmarkSeconds -and $speed -gt 0) -or
			($_.CurrentTime.Elapsed.TotalSeconds -ge ($_.Miner.BenchmarkSeconds * 2) -and $speed -eq 0)) {
				$_.Stop()
			if ($speed -eq 0) {
				$speed = $Statistics.SetValue($_.Miner.GetFilename(), $_.Miner.GetKey(), -1)
			}
			else {
				$speed = $Statistics.SetValue($_.Miner.GetFilename(), $_.Miner.GetKey(), $speed, $Config.AverageHashSpeed)
			}
		}
	}
	
	# read speed and price of proposed miners
	$AllMiners = $AllMiners | ForEach-Object {
		if (!$FastLoop) {
			$speed = $Statistics.GetValue($_.GetFilename(), $_.GetKey())
			# filter unused
			if ($speed -ge 0) {
				$price = (Get-Pool $_.Algorithm).Profit
				[MinerProfitInfo]::new($_, $speed, $price)
				Remove-Variable price
			}
		}
		elseif (!$exit) {
			$speed = $Statistics.GetValue($_.Miner.GetFilename(), $_.Miner.GetKey())
			# filter unused
			if ($speed -ge 0) {
				$_.SetSpeed($speed)
				$_
			}
		}
	}

	if (!$exit) {
		Remove-Variable speed
	
		# look for run or stop miner
		[Config]::ActiveTypes | ForEach-Object {
			$type = $_

			$allMinersByType = $AllMiners | Where-Object { $_.Miner.Type -eq $type }
			$activeMinersByType = $ActiveMiners.Values | Where-Object { $_.Miner.Type -eq $type }

			# run for bencmark - exclude failed
			$run = $allMinersByType | Where-Object { $Statistics.GetValue($_.Miner.GetFilename(), $_.Miner.GetKey()) -eq 0 } | Select-Object -First 1

			# nothing benchmarking - get most profitable - exclude failed
			if (!$run) {
				$miner = $null
				$allMinersByType | Where-Object { $_.Profit -gt 0 } | ForEach-Object {
					if ($run -eq $null -or $_.Profit -gt $run.Profit) {
						# skip failed or nohash miners
						$miner = $_
						if (($activeMinersByType | Where-Object { $_.State -eq [eState]::NoHash -or $_.State -eq [eState]::Failed } |
							Where-Object { $miner.Miner.GetUniqueKey() -eq $_.Miner.GetUniqueKey() }) -eq $null) {
							$run = $_
						}
					}
				}
				Remove-Variable miner
			}

			if ($run) {
				$miner = $run.Miner
				if (!$ActiveMiners.ContainsKey($miner.GetUniqueKey())) {
					$ActiveMiners.Add($miner.GetUniqueKey(), [MinerProcess]::new($miner, $Config))
				}
				#stop not choosen
				$activeMinersByType | Where-Object { $miner.GetUniqueKey() -ne $_.Miner.GetUniqueKey() } | ForEach-Object {
					$_.Stop()
				}
				# run choosen
				$mi = $ActiveMiners[$miner.GetUniqueKey()]
				if ($mi.State -eq $null -or $mi.State -ne [eState]::Running) {
					if ($Statistics.GetValue($mi.Miner.GetFilename(), $mi.Miner.GetKey()) -eq 0) {
						$mi.Benchmark()
					}
					else {
						$mi.Start()
					}
					$FastLoop = $false
				}
				Remove-Variable mi, miner
			}
			Remove-Variable run, activeMinersByType, allMinersByType, type
		}
	}
	
	$Statistics.Write()

	if (!$FastLoop) {
		$Summary.LoopTime.Reset()
		$Summary.LoopTime.Start()
	}

	Clear-Host
	Out-Header
	
	# $AllPools | Select-Object -Property * -ExcludeProperty @("StablePrice", "PriceFluctuation") | Format-Table | Out-Host
	$AllMiners | Sort-Object @{ Expression = { $_.Miner.Type } },
		@{Expression = { $_.Profit }; Descending = $True},
		@{Expression = { $_.Miner.Algorithm } },
		@{Expression = { $_.Miner.ExtraArgs } } |
		Format-Table @{ Label="Miner"; Expression = { $_.Miner.Name } },
			@{ Label="Algorithm"; Expression = { $_.Miner.Algorithm } },
			@{ Label="Speed, H/s"; Expression = { if ($_.Speed -eq 0) { "Testing" } else { [MultipleUnit]::ToString($_.Speed) } }; Alignment="Right" },
			@{ Label="mBTC/Day"; Expression = { if ($_.Profit -eq 0) { "$($_.Miner.BenchmarkSeconds) sec" } else { $_.Profit * 1000 } }; FormatString = "N5" },
			@{ Label="BTC/GH/Day"; Expression = { $_.Price * 1000000000 }; FormatString = "N8" },
			@{ Label="Pool"; Expression = { $_.Miner.Pool } },
			@{ Label="ExtraArgs"; Expression = { $_.Miner.ExtraArgs } } -GroupBy @{ Label="Type"; Expression = { $_.Miner.Type } } | Out-Host
			#@{ Label="Arguments"; Expression = { $_.Miner.Arguments } }

	# display active miners
	$ActiveMiners.Values | Sort-Object { [int]($_.State -as [eState]), [SummaryInfo]::Elapsed($_.TotalTime.Elapsed) } |
		Format-Table @{ Label="Type"; Expression = { $_.Miner.Type } },
			@{ Label="Algorithm"; Expression = { $_.Miner.Algorithm } },
			@{ Label="Speed, H/s"; Expression = { $speed = $_.GetSpeed(); if ($speed -eq 0) { "Unknown" } else { [MultipleUnit]::ToString($speed) } }; Alignment="Right"; },
			@{ Label="Run Time"; Expression = { [SummaryInfo]::Elapsed($_.TotalTime.Elapsed) }; Alignment = "Right" },
			@{ Label="Run"; Expression = { if ($_.Run -eq 1) { "Once" } else { $_.Run } } },
			@{ Label="Command"; Expression = { $_.Miner.GetCommandLine() } } -GroupBy State -Wrap | Out-Host

	Out-Footer

	do {
		if ($FastLoop -eq $false) {
			Start-Sleep -Seconds $Config.CheckTimeout
		}
		$FastLoop = $false

<#		while ([Console]::KeyAvailable -eq $true) {
			[ConsoleKeyInfo] $key = [Console]::ReadKey($true)
			if ($key.Key -eq [ConsoleKey]::V) {
				Write-Host "Verbose level changed" -ForegroundColor Green
			}
			elseif ($key.Modifiers -match [ConsoleModifiers]::Alt -or $key.Modifiers -match [ConsoleModifiers]::Control) {
				if ($key.Key -eq [ConsoleKey]::C -or $key.Key -eq [ConsoleKey]::E -or $key.Key -eq [ConsoleKey]::Q -or $key.Key -eq [ConsoleKey]::X) {
					$exit = $true
				}
			}
		}
#>
		# if needed - exit
		if ($exit -eq $true) {
			Write-Host "Exiting ..." -ForegroundColor Green
			$ActiveMiners.Values | Where-Object { $_.State -eq [eState]::Running } | ForEach-Object {
				$_.Stop()
			}
			exit
		}

		# read speed while run main loop timeout
		if ($ActiveMiners.Values -and $ActiveMiners.Values.Length -gt 0) {
			Get-Speed $ActiveMiners.Values
		}
		# check miners work propertly
		$ActiveMiners.Values | Where-Object { $_.State -eq [eState]::Running -or $_.State -eq [eState]::NoHash } | ForEach-Object {
			if ($_.Check() -eq [eState]::Failed) {
				# miner failed - run next
				if ($_.Action -eq [eAction]::Benchmark) {
					$speed = $Statistics.SetValue($_.Miner.GetFilename(), $_.Miner.GetKey(), -1)
					Remove-Variable speed
				}
				$FastLoop = $true
			}
			# benchmark time reached - exit from loop
			elseif ($_.Action -eq [eAction]::Benchmark -and $_.CurrentTime.Elapsed.TotalSeconds -ge $_.Miner.BenchmarkSeconds -and $_.GetSpeed() -gt 0) {
				$FastLoop = $true
			}
		}
	} while ($Config.LoopTimeout -gt $Summary.LoopTime.Elapsed.TotalSeconds -and !$FastLoop)

	# if timeout reached - normal loop
	if ($Config.LoopTimeout -le $Summary.LoopTime.Elapsed.TotalSeconds) {
		$FastLoop = $false
	}

	if (!$FastLoop) {
		Remove-Variable AllPools, AllMiners
		[GC]::Collect()
	}
	
	$Summary.Loop++
}