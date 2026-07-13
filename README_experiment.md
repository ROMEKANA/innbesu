# Shannon Entropy and ZIP Compression Experiment

## 実験目的

シャノンエントロピーとZIP圧縮率の関係を、人工データと実ファイルで比較する。

## エントロピーの定義

すべてのファイルをバイト列として扱い、各バイト値の出現確率を `p_i` として次で計算する。

```text
H = -sum(p_i * log2(p_i))
```

単位は `bit/byte`。

## 圧縮率の定義

```text
compression_ratio = compressed_bytes / original_bytes
```

値が小さいほど、よく圧縮できていることを表す。圧縮はPowerShell標準の `Compress-Archive` によるZIP形式。

## 3種類の実験内容

- `A` と `B` の出現確率を変え、偏りとエントロピー・圧縮率の関係を調べる。
- `A` と `B` が50%ずつのデータで、並び方だけを変えて圧縮率を比較する。
- 文章、ソースコード、CSV、PNG、JPEG、ランダムバイナリを比較する。

## 入力に使用した実ファイル

- `original_data/texts/wagahaiwa_nekodearu.txt`
- `original_data/texts/Alice’sAdventuresinWonderland.txt`
- `original_data/C-Plus-Plus-master_math` 内の `.cpp` と `.h`
- `original_data/iris/iris.data`
- `original_data/images/Anderson's_Iris_data_set.png`
- `original_data/images/Anderson's_Iris_data_set.jpeg`
- `generated/random/random_1mib.bin`

## 実行方法

```powershell
.\run_experiment.ps1
```

実ファイルの入力元は `original_data` ディレクトリ。

実行ポリシーで止まる場合:

```powershell
powershell -ExecutionPolicy Bypass -File .\run_experiment.ps1
```

## 4種類のCSVの用途

- `results/graph1_bias_entropy.csv`: 文字の偏りとエントロピーのグラフ用。
- `results/graph2_entropy_compression.csv`: エントロピーと圧縮率の散布図用。
- `results/graph3_order_comparison.csv`: 同じエントロピーで並び方が違うデータの比較用。
- `results/graph4_real_files.csv`: 実ファイル種類ごとの比較用。

## 注意

- 解析は文字ではなくバイト単位で行う。
- 圧縮率はZIP形式での値であり、ZIPヘッダーも含む。
- Iris CSVはサイズが小さいため、ZIPヘッダーの影響を受けやすい。
- 単一バイトのエントロピーだけでは、長い周期やデータの並び方を完全には表現できない。
