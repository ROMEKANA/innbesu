$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $Root

$InputRoot = Join-Path $Root "original_data"
$InputTexts = Join-Path $InputRoot "texts"
$InputImages = Join-Path $InputRoot "images"
$InputIris = Join-Path $InputRoot "iris"
$InputCpp = Join-Path $InputRoot "C-Plus-Plus-master_math"
$Utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$Culture = [System.Globalization.CultureInfo]::InvariantCulture
$TotalSize = 1048576

function Ensure-Directory($Path)
{
	New-Item -ItemType Directory -Force -Path $Path | Out-Null
}

function Remove-GeneratedFiles
{
	Remove-Item -Path "generated\bias\*.bin" -Force -ErrorAction SilentlyContinue
	Remove-Item -Path "generated\order\*.bin" -Force -ErrorAction SilentlyContinue
	Remove-Item -Path "generated\random\*.bin" -Force -ErrorAction SilentlyContinue
	Remove-Item -Path "prepared\*" -Force -ErrorAction SilentlyContinue
	Remove-Item -Path "compressed\*.zip" -Force -ErrorAction SilentlyContinue
	Remove-Item -Path "results\*.csv" -Force -ErrorAction SilentlyContinue
}

function Find-Compiler
{
	$cmd = Get-Command gcc -ErrorAction SilentlyContinue
	if ($null -ne $cmd) {
		$line = (& gcc --version | Select-Object -First 1)
		return @{ Command = "gcc"; Version = $line }
	}

	$cmd = Get-Command clang -ErrorAction SilentlyContinue
	if ($null -ne $cmd) {
		$line = (& clang --version | Select-Object -First 1)
		return @{ Command = "clang"; Version = $line }
	}

	throw "gcc or clang was not found"
}

function Compile-C($Compiler, $Source, $Output)
{
	$argsWithLm = @("-std=c17", "-O2", "-Wall", "-Wextra", "-pedantic", $Source, "-o", $Output, "-lm")
	& $Compiler @argsWithLm
	if ($LASTEXITCODE -eq 0) {
		return
	}

	$argsNoLm = @("-std=c17", "-O2", "-Wall", "-Wextra", "-pedantic", $Source, "-o", $Output)
	& $Compiler @argsNoLm
	if ($LASTEXITCODE -ne 0) {
		throw "compile failed: $Source"
	}
}

function Run-Exe($Path)
{
	& $Path
	if ($LASTEXITCODE -ne 0) {
		throw "execution failed: $Path"
	}
}

function Binary-Entropy($p)
{
	if ($p -le 0.0 -or $p -ge 1.0) {
		return 0.0
	}
	return -$p * [Math]::Log($p, 2.0) - (1.0 - $p) * [Math]::Log(1.0 - $p, 2.0)
}

function Format-Number($Value)
{
	if ([double]::IsNaN($Value) -or [double]::IsInfinity($Value)) {
		throw "invalid numeric value"
	}
	return $Value.ToString("0.000000000", $Culture)
}

function Analyze-File($Path)
{
	$output = & ".\bin\analyze_file.exe" $Path
	if ($LASTEXITCODE -ne 0) {
		throw "analysis failed: $Path"
	}

	$parts = $output.Trim().Split(",")
	if ($parts.Count -ne 2) {
		throw "invalid analysis output: $Path"
	}

	return @{
		OriginalBytes = [uint64]::Parse($parts[0], $Culture)
		Entropy = [double]::Parse($parts[1], $Culture)
	}
}

function Measure-Compressed($Path, $ZipName)
{
	$zipPath = Join-Path "compressed" $ZipName
	Compress-Archive -Path $Path -DestinationPath $zipPath -CompressionLevel Optimal -Force
	$zip = Get-Item -LiteralPath $zipPath
	if ($zip.Length -le 0) {
		throw "compressed size is not positive: $zipPath"
	}
	return @{ Path = $zipPath; Bytes = [uint64]$zip.Length }
}

function Make-Record($Group, $Name, $Path, $ZipName)
{
	$analysis = Analyze-File $Path
	$zip = Measure-Compressed $Path $ZipName
	if ($analysis.OriginalBytes -le 0) {
		throw "original size is not positive: $Path"
	}

	$ratio = [double]$zip.Bytes / [double]$analysis.OriginalBytes
	if ($ratio -le 0.0) {
		throw "compression ratio is not positive: $Path"
	}

	return [pscustomobject]@{
		Group = $Group
		Name = $Name
		Path = $Path
		Entropy = $analysis.Entropy
		OriginalBytes = $analysis.OriginalBytes
		CompressedBytes = $zip.Bytes
		CompressionRatio = $ratio
	}
}

function Write-Lines($Path, $Lines)
{
	[System.IO.File]::WriteAllLines((Join-Path $Root $Path), $Lines, $Utf8NoBom)
}

function Validate-Csv($Path, $ExpectedLines)
{
	$lines = [System.IO.File]::ReadAllLines((Join-Path $Root $Path), [System.Text.Encoding]::UTF8)
	if ($lines.Count -ne $ExpectedLines) {
		throw "unexpected CSV line count: $Path"
	}

	foreach ($line in $lines) {
		if ($line -match "NaN|Infinity|-Infinity") {
			throw "invalid numeric text in CSV: $Path"
		}
		$fields = $line.Split(",")
		foreach ($field in $fields) {
			if ($field.Length -eq 0) {
				throw "empty field in CSV: $Path"
			}
		}
	}
}

Ensure-Directory "src"
Ensure-Directory "bin"
Ensure-Directory "generated\bias"
Ensure-Directory "generated\order"
Ensure-Directory "generated\random"
Ensure-Directory "prepared"
Ensure-Directory "compressed"
Ensure-Directory "results"
if (-not (Test-Path -LiteralPath $InputRoot)) {
	throw "original_data directory was not found"
}
Remove-GeneratedFiles

$compiler = Find-Compiler
Write-Host ("compiler: " + $compiler.Version)

$programs = @(
	@{ Source = "src\analyze_file.c"; Output = "bin\analyze_file.exe" },
	@{ Source = "src\gen_bias_p000.c"; Output = "bin\gen_bias_p000.exe" },
	@{ Source = "src\gen_bias_p010.c"; Output = "bin\gen_bias_p010.exe" },
	@{ Source = "src\gen_bias_p020.c"; Output = "bin\gen_bias_p020.exe" },
	@{ Source = "src\gen_bias_p030.c"; Output = "bin\gen_bias_p030.exe" },
	@{ Source = "src\gen_bias_p040.c"; Output = "bin\gen_bias_p040.exe" },
	@{ Source = "src\gen_bias_p050.c"; Output = "bin\gen_bias_p050.exe" },
	@{ Source = "src\gen_bias_p060.c"; Output = "bin\gen_bias_p060.exe" },
	@{ Source = "src\gen_bias_p070.c"; Output = "bin\gen_bias_p070.exe" },
	@{ Source = "src\gen_bias_p080.c"; Output = "bin\gen_bias_p080.exe" },
	@{ Source = "src\gen_bias_p090.c"; Output = "bin\gen_bias_p090.exe" },
	@{ Source = "src\gen_bias_p100.c"; Output = "bin\gen_bias_p100.exe" },
	@{ Source = "src\gen_order_alternating.c"; Output = "bin\gen_order_alternating.exe" },
	@{ Source = "src\gen_order_small_blocks.c"; Output = "bin\gen_order_small_blocks.exe" },
	@{ Source = "src\gen_order_large_blocks.c"; Output = "bin\gen_order_large_blocks.exe" },
	@{ Source = "src\gen_order_shuffled.c"; Output = "bin\gen_order_shuffled.exe" },
	@{ Source = "src\gen_random_bytes.c"; Output = "bin\gen_random_bytes.exe" }
)

foreach ($program in $programs) {
	Compile-C $compiler.Command $program.Source $program.Output
}

$generators = $programs | Where-Object { $_.Source -ne "src\analyze_file.c" }
foreach ($program in $generators) {
	Run-Exe (".\" + $program.Output)
}

Copy-Item -LiteralPath (Join-Path $InputTexts "wagahaiwa_nekodearu.txt") -Destination "prepared\japanese_text.txt" -Force
$alice = Get-ChildItem -LiteralPath $InputTexts -File | Where-Object {
	$_.Name -like "Alice*Wonderland.txt"
} | Select-Object -First 1
if ($null -eq $alice) {
	throw "Alice text file was not found"
}
Copy-Item -LiteralPath $alice.FullName -Destination "prepared\english_text.txt" -Force
Copy-Item -LiteralPath (Join-Path $InputImages "Anderson's_Iris_data_set.png") -Destination "prepared\iris_image.png" -Force
Copy-Item -LiteralPath (Join-Path $InputImages "Anderson's_Iris_data_set.jpeg") -Destination "prepared\iris_image.jpeg" -Force
Copy-Item -LiteralPath (Join-Path $InputIris "iris.data") -Destination "prepared\iris.csv" -Force
Copy-Item -LiteralPath "generated\random\random_1mib.bin" -Destination "prepared\random_1mib.bin" -Force

$cppOut = Join-Path $Root "prepared\cpp_sources.txt"
$writer = [System.IO.StreamWriter]::new($cppOut, $false, $Utf8NoBom)
try {
	$cppFiles = Get-ChildItem -LiteralPath $InputCpp -File |
		Where-Object { $_.Extension -eq ".cpp" -or $_.Extension -eq ".h" } |
		Sort-Object Name
	foreach ($file in $cppFiles) {
		$writer.WriteLine(("/* FILE: {0} */" -f $file.Name))
		$text = [System.IO.File]::ReadAllText($file.FullName, [System.Text.Encoding]::UTF8)
		$writer.WriteLine($text)
	}
} finally {
	$writer.Close()
}

$biasDefs = @(
	@{ Name = "bias_p000"; PA = 0.0; Path = "generated\bias\bias_p000.bin" },
	@{ Name = "bias_p010"; PA = 0.1; Path = "generated\bias\bias_p010.bin" },
	@{ Name = "bias_p020"; PA = 0.2; Path = "generated\bias\bias_p020.bin" },
	@{ Name = "bias_p030"; PA = 0.3; Path = "generated\bias\bias_p030.bin" },
	@{ Name = "bias_p040"; PA = 0.4; Path = "generated\bias\bias_p040.bin" },
	@{ Name = "bias_p050"; PA = 0.5; Path = "generated\bias\bias_p050.bin" },
	@{ Name = "bias_p060"; PA = 0.6; Path = "generated\bias\bias_p060.bin" },
	@{ Name = "bias_p070"; PA = 0.7; Path = "generated\bias\bias_p070.bin" },
	@{ Name = "bias_p080"; PA = 0.8; Path = "generated\bias\bias_p080.bin" },
	@{ Name = "bias_p090"; PA = 0.9; Path = "generated\bias\bias_p090.bin" },
	@{ Name = "bias_p100"; PA = 1.0; Path = "generated\bias\bias_p100.bin" }
)

$orderDefs = @(
	@{ Name = "alternating"; Pattern = "ABAB"; Path = "generated\order\order_alternating.bin" },
	@{ Name = "small_blocks"; Pattern = "AAAABBBB"; Path = "generated\order\order_small_blocks.bin" },
	@{ Name = "large_blocks"; Pattern = "half_A_half_B"; Path = "generated\order\order_large_blocks.bin" },
	@{ Name = "shuffled"; Pattern = "shuffled_equal_counts"; Path = "generated\order\order_shuffled.bin" }
)

$realDefs = @(
	@{ Name = "japanese_text"; FileType = "text"; Path = "prepared\japanese_text.txt" },
	@{ Name = "english_text"; FileType = "text"; Path = "prepared\english_text.txt" },
	@{ Name = "cpp_sources"; FileType = "source_code"; Path = "prepared\cpp_sources.txt" },
	@{ Name = "iris_csv"; FileType = "csv"; Path = "prepared\iris.csv" },
	@{ Name = "png_image"; FileType = "png"; Path = "prepared\iris_image.png" },
	@{ Name = "jpeg_image"; FileType = "jpeg"; Path = "prepared\iris_image.jpeg" },
	@{ Name = "random_binary"; FileType = "binary"; Path = "prepared\random_1mib.bin" }
)

$biasRecords = @()
foreach ($item in $biasDefs) {
	$record = Make-Record "bias" $item.Name $item.Path ($item.Name + ".zip")
	$record | Add-Member -NotePropertyName PA -NotePropertyValue $item.PA
	$record | Add-Member -NotePropertyName TheoreticalEntropy -NotePropertyValue (Binary-Entropy $item.PA)
	$biasRecords += $record
}

$orderRecords = @()
foreach ($item in $orderDefs) {
	$record = Make-Record "order" $item.Name $item.Path ("order_" + $item.Name + ".zip")
	$record | Add-Member -NotePropertyName Pattern -NotePropertyValue $item.Pattern
	$orderRecords += $record
}

$realRecords = @()
foreach ($item in $realDefs) {
	$record = Make-Record "real" $item.Name $item.Path ($item.Name + ".zip")
	$record | Add-Member -NotePropertyName FileType -NotePropertyValue $item.FileType
	$realRecords += $record
}

$graph1 = @("name,p_a,theoretical_entropy,measured_entropy,original_bytes,compressed_bytes,compression_ratio")
foreach ($r in $biasRecords | Sort-Object PA) {
	$graph1 += ($r.Name + "," + (Format-Number $r.PA) + "," + (Format-Number $r.TheoreticalEntropy) + "," + (Format-Number $r.Entropy) + "," + $r.OriginalBytes + "," + $r.CompressedBytes + "," + (Format-Number $r.CompressionRatio))
}
Write-Lines "results\graph1_bias_entropy.csv" $graph1

$graph2 = @("group,name,entropy_bits_per_byte,original_bytes,compressed_bytes,compression_ratio")
foreach ($r in @($biasRecords + $orderRecords + $realRecords)) {
	$graph2 += ($r.Group + "," + $r.Name + "," + (Format-Number $r.Entropy) + "," + $r.OriginalBytes + "," + $r.CompressedBytes + "," + (Format-Number $r.CompressionRatio))
}
Write-Lines "results\graph2_entropy_compression.csv" $graph2

$graph3 = @("name,pattern,entropy_bits_per_byte,original_bytes,compressed_bytes,compression_ratio")
foreach ($r in $orderRecords) {
	$graph3 += ($r.Name + "," + $r.Pattern + "," + (Format-Number $r.Entropy) + "," + $r.OriginalBytes + "," + $r.CompressedBytes + "," + (Format-Number $r.CompressionRatio))
}
Write-Lines "results\graph3_order_comparison.csv" $graph3

$graph4 = @("name,file_type,entropy_bits_per_byte,original_bytes,compressed_bytes,compression_ratio")
foreach ($r in $realRecords) {
	$graph4 += ($r.Name + "," + $r.FileType + "," + (Format-Number $r.Entropy) + "," + $r.OriginalBytes + "," + $r.CompressedBytes + "," + (Format-Number $r.CompressionRatio))
}
Write-Lines "results\graph4_real_files.csv" $graph4

if ((Get-ChildItem -LiteralPath "generated\bias" -Filter "*.bin").Count -ne 11) {
	throw "bias file count check failed"
}
if ((Get-ChildItem -LiteralPath "generated\order" -Filter "*.bin").Count -ne 4) {
	throw "order file count check failed"
}
if (-not (Test-Path -LiteralPath "generated\random\random_1mib.bin")) {
	throw "random file check failed"
}
foreach ($file in Get-ChildItem -LiteralPath "generated" -Filter "*.bin" -Recurse) {
	if ($file.Length -ne $TotalSize) {
		throw "artificial file size check failed: $($file.FullName)"
	}
}

$eps = 1e-9
$bias0 = ($biasRecords | Where-Object { $_.Name -eq "bias_p000" }).Entropy
$bias1 = ($biasRecords | Where-Object { $_.Name -eq "bias_p100" }).Entropy
$biasHalf = ($biasRecords | Where-Object { $_.Name -eq "bias_p050" }).Entropy
if ([Math]::Abs($bias0) -ge $eps -or [Math]::Abs($bias1) -ge $eps) {
	throw "endpoint entropy check failed"
}
if ([Math]::Abs($biasHalf - 1.0) -ge $eps) {
	throw "p_a=0.5 entropy check failed"
}
foreach ($record in $orderRecords) {
	if ([Math]::Abs($record.Entropy - 1.0) -ge $eps) {
		throw "order entropy check failed: $($record.Name)"
	}
}
$randomEntropy = ($realRecords | Where-Object { $_.Name -eq "random_binary" }).Entropy
if ($randomEntropy -lt 7.99) {
	throw "random entropy check failed"
}

foreach ($record in @($biasRecords + $orderRecords + $realRecords)) {
	if ($record.OriginalBytes -le 0 -or $record.CompressedBytes -le 0 -or $record.CompressionRatio -le 0.0) {
		throw "positive size or ratio check failed: $($record.Name)"
	}
}

Validate-Csv "results\graph1_bias_entropy.csv" 12
Validate-Csv "results\graph2_entropy_compression.csv" 23
Validate-Csv "results\graph3_order_comparison.csv" 5
Validate-Csv "results\graph4_real_files.csv" 8

Write-Host "completed"
