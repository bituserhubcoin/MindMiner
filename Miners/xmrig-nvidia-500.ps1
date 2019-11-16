<#
MindMiner  Copyright (C) 2018-2019  Oleg Samsonov aka Quake4
https://github.com/Quake4/MindMiner
License GPL-3.0
#>

if ([Config]::ActiveTypes -notcontains [eMinerType]::nVidia) { exit }
if (![Config]::Is64Bit) { exit }
if ([Config]::CudaVersion -lt [version]::new(10, 1)) { return }

$Name = (Get-Item $script:MyInvocation.MyCommand.Path).BaseName

$Cfg = ReadOrCreateMinerConfig "Do you want use to mine the '$Name' miner" ([IO.Path]::Combine($PSScriptRoot, $Name + [BaseConfig]::Filename)) @{
	Enabled = $true
	BenchmarkSeconds = 90
	ExtraArgs = $null
	Algorithms = @(
		[AlgoInfoEx]@{ Enabled = $true; Algorithm = "rx/0" }
		[AlgoInfoEx]@{ Enabled = $true; Algorithm = "cn/r" }
)}

if (!$Cfg.Enabled) { return }

$file = [IO.Path]::Combine($BinLocation, $Name, "config.json")
if ([IO.File]::Exists($file)) {
	[IO.File]::Delete($file)
}
<#
switch ([Config]::CudaVersion) {
	{ $_ -ge [version]::new(10, 1) } { $url = "https://github.com/xmrig/xmrig-nvidia/releases/download/v2.14.5/xmrig-nvidia-2.14.5-cuda10_1-win64.zip" }
	([version]::new(10, 0)) { $url = "https://github.com/xmrig/xmrig-nvidia/releases/download/v2.14.5/xmrig-nvidia-2.14.5-cuda10-win64.zip" }
	([version]::new(9, 2)) { $url = "https://github.com/xmrig/xmrig-nvidia/releases/download/v2.14.5/xmrig-nvidia-2.14.5-cuda9_2-win64.zip" }
	([version]::new(9, 1)) { $url = "https://github.com/xmrig/xmrig-nvidia/releases/download/v2.14.5/xmrig-nvidia-2.14.5-cuda9_1-win64.zip" }
	([version]::new(9, 0)) { $url = "https://github.com/xmrig/xmrig-nvidia/releases/download/v2.14.5/xmrig-nvidia-2.14.5-cuda9_0-win64.zip" }
	default { $url = "https://github.com/xmrig/xmrig-nvidia/releases/download/v2.14.5/xmrig-nvidia-2.14.5-cuda8-win64.zip" }
}
#>
$Cfg.Algorithms | ForEach-Object {
	if ($_.Enabled) {
		$Algo = Get-Algo($_.Algorithm)
		if ($Algo) {
			# find pool by algorithm
			$Pool = Get-Pool($Algo)
			if ($Pool) {
				$extrargs = Get-Join " " @($Cfg.ExtraArgs, $_.ExtraArgs)
				[MinerInfo]@{
					Pool = $Pool.PoolName()
					PoolKey = $Pool.PoolKey()
					Name = $Name
					Algorithm = $Algo
					Type = [eMinerType]::nVidia
					API = "xmrig2"
					URI = "https://github.com/xmrig/xmrig/releases/download/v5.0.0/xmrig-5.0.0-msvc-cuda10_1-win64.zip"
					Path = "$Name\xmrig.exe"
					ExtraArgs = $extrargs
					Arguments = "-a $($_.Algorithm) -o $($Pool.Host):$($Pool.PortUnsecure) -u $($Pool.User) -p $($Pool.Password) -R $($Config.CheckTimeout) --api-port=4043 --donate-level=1 --cuda --no-nvml $extrargs"
					Port = 4043
					BenchmarkSeconds = if ($_.BenchmarkSeconds) { $_.BenchmarkSeconds } else { $Cfg.BenchmarkSeconds }
					RunBefore = $_.RunBefore
					RunAfter = $_.RunAfter
					Fee = 1
				}
			}
		}
	}
}