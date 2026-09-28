# AdobeCommerce テスト環境構築プロジェクト

## 目的
Adobe Commerce を本番と同様の構成で構築し、New Relic と接続してオブザーバビリティ獲得の訓練の土台とする。

Adobe Commerce の無料版 = **Magento Open Source 2.4.9** を AWS 東京リージョンに ECS Fargate で構築する。
インストール元は Mage-OS が運営する公式ミラー(mirror.mage-os.org)で、Adobe の認証キーは不要。

## 構成

構成図: [docs/architecture.svg](docs/architecture.svg)(AWS Architecture Icons 2026-07 版で作成。`docs/build-architecture-svg.ps1` で再生成可能)

```
Internet ──> Route 53 (actest.examp1e.site) ──> AWS WAF ──> ALB (public subnet, :443 HTTPS / :80→443)
               └─> ECS Fargate service "web"  (private subnet, 2 vCPU / 8 GB)
                     task: varnish(:80) ─> nginx(:8080) ─> php-fpm(:9000)
                           + log_router (FireLens → New Relic Logs)      ← ライセンスキー設定時のみ
                           + newrelic-infra (nri-ecs, Fargate モード)      ← ライセンスキー設定時のみ
             ECS Fargate service "cron" (1 task: bin/magento cron:run ループ + キューコンシューマ)
             ECS task "install"  (初回 setup:install / 以後 setup:upgrade。手動実行)

  データ層 (private subnet):
    RDS MySQL 8.4 (db.t4g.medium, 拡張モニタリング + Performance Insights + slow query log)
    ElastiCache Valkey 9 (cache.t4g.small: Magento キャッシュ + セッション)
    OpenSearch 3.3 (t3.small.search: 商品検索)
    EFS (pub/media を全タスクで共有)

  その他: ECR ×2 (magento / varnish) / SSM Parameter Store (秘密情報) / CloudWatch Logs / NAT Gateway
          ACM 証明書 (DNS 検証) / Route 53 A レコード (alias → ALB) / WAF ログ (CloudWatch Logs)
          CloudWatch Metric Streams → Kinesis Firehose → New Relic (AWS メトリクス)  ← キー設定時のみ
```

### 公開 URL と WAF
- URL は **https://actest.examp1e.site/**(`domain_name` / `route53_zone_name` 変数。examp1e.site はこのアカウントの Route 53 ホストゾーン)。証明書は ACM が発行し、Route 53 で DNS 検証する。HTTP は HTTPS へリダイレクト。
- ALB には **AWS WAF**(regional)を関連付け: AWS マネージドルール(IP reputation / Common / KnownBadInputs / SQLi)+ IP ごとのレート制限(5 分で 3000 リクエスト)。Magento 管理画面の大きな POST や HTML 入力を誤検知する Common ルール(SizeRestrictions_BODY, CrossSiteScripting_BODY, GenericRFI_BODY)は COUNT モード。BLOCK / COUNT のログは CloudWatch Logs `aws-waf-logs-sunfish-test` に出る。

ディレクトリ:

| パス | 内容 |
|---|---|
| `infra/` | Terraform 一式(VPC, ALB, ECS, RDS, ElastiCache, OpenSearch, EFS, ECR, SSM, New Relic 連携) |
| `docker/magento/` | Magento イメージ(php-fpm + nginx 同梱、New Relic PHP エージェント同梱、`entrypoint.sh` が役割を切替) |
| `docker/varnish/` | Varnish イメージ(Magento 同梱の VCL テンプレートから生成) |
| `scripts/` | PowerShell スクリプト(`tf.ps1`, `build-push.ps1`, `run-install.ps1`, `scale.ps1`) |

## 前提

- Windows + PowerShell、Terraform 1.6 以上、AWS CLI v2、Docker Desktop(Linux コンテナ)
- リポジトリ直下の `.env` に `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY`(スクリプトが読み込む)
- ECS Exec(コンテナに入る)を使う場合のみ `session-manager-plugin`(`winget install Amazon.SessionManagerPlugin`)

## 構築手順

```powershell
# 1. Terraform 初期化と apply(約 25 分。OpenSearch と RDS の作成が長い)
.\scripts\tf.ps1 init
.\scripts\tf.ps1 apply

# 2. イメージをローカルでビルドして ECR へ push(初回 20〜30 分、約 1 GB ダウンロード)
#    infra/image_tag.auto.tfvars にタグが書き出される
.\scripts\build-push.ps1

# 3. 新しいイメージタグで ECS サービスを更新
.\scripts\tf.ps1 apply

# 4. 初回インストール(DB 初期化 + サンプルデータ投入 + 再インデックス。15〜30 分)
.\scripts\run-install.ps1

# 5. URL と管理者パスワード
.\scripts\tf.ps1 output storefront_url
.\scripts\tf.ps1 output admin_url
.\scripts\tf.ps1 output -raw admin_password_command | Invoke-Expression
```

インストール完了後、web タスクのヘルスチェック(`/health_check.php`)が通ると https://actest.examp1e.site/ でストアフロントが開く。
管理画面は `https://actest.examp1e.site/admin/`、ユーザーは `admin`(2 要素認証モジュールは無効化済み)。

### 仕組みのポイント

- **イメージ**: ビルド時に composer で Magento を取得し、`setup:di:compile` と `setup:static-content:deploy` まで済ませて本番モードにする(DB 不要)。
- **設定**: 起動時に `entrypoint.sh` が環境変数(RDS / Valkey / OpenSearch のエンドポイント、SSM から注入される秘密情報)から `app/etc/env.php` を生成する。暗号鍵(crypt key)は SSM に保存され全タスクで共通。
- **Varnish**: ALB のヘルスチェックと外部リクエストは Varnish(:80)が受け、nginx(:8080)→ php-fpm(:9000)へ流れる。同一タスク内なので localhost 通信。Magento からのパージも localhost に送られる(web タスクを複数にすると他タスクのキャッシュは残る点に注意)。
- **install タスク**: DB に `core_config_data` が無ければ `setup:install`、あれば `setup:upgrade --keep-generated`。イメージ更新後の DB マイグレーションにも使う。
- **DB ユーザー**: RDS のマスターユーザー(`magento`)は権限を `rds_superuser_role` 経由で持つため、Magento の権限チェック(SHOW GRANTS の直接付与のみを見る)に落ちる。install タスクが `magento_app` ユーザーを作り `magento` スキーマに直接 GRANT し、全コンテナはこのユーザーで接続する(パスワードはマスターと同じ SSM の値)。
- **Varnish コンテナ**: Fargate では非 root ユーザーが :80 を bind できないため root で起動(varnishd がワーカーを降格)。
- **サンプルデータ**: production モードでは投入に失敗する(MSI の在庫テーブルが未作成で "Could not receive Stock Item data"、Adobe KB「Errors installing optional sample data」)。install タスクだけ `MAGE_MODE=developer` で動かす。画像は composer がイメージの `pub/media` に置くが EFS マウントで隠れるため、install タスクが `vendor/magento/sample-data-media` から EFS に投入し、`media-gallery:sync` で登録する。
- **install 後のキャッシュ**: install タスクからの Varnish パージは届かないので、`run-install.ps1` が最後に web サービスを再デプロイして Varnish を空の状態で起動し直す。

## New Relic 連携

### 1. キーの種類
New Relic の右上ユーザーメニュー → **API keys** に 2 種類ある。

| キー | 形式 | 用途 | このリポジトリでの使い方 |
|---|---|---|---|
| **INGEST - LICENSE**(ライセンスキー) | 40 文字、末尾 `NRAL` | APM / ログ / インフラ / メトリクスの**送信** | `infra/terraform.tfvars` の `newrelic_license_key` |
| **USER**(ユーザー API キー) | `NRAK-` で始まる 32 文字 | NerdGraph / REST API の**操作**(AWS アカウント連携、Synthetics、アラート、Terraform newrelic provider) | `.env` の `NEWRELIC_API_KEY`。ライセンスキーの取得にも使える(下記) |

`.env` の `NEWRELIC_API_KEY` は USER キーなので、ライセンスキーは NerdGraph で取得できる(アカウント 8557812、US データセンター):

```powershell
# User キーでアカウントのライセンスキー一覧を取得(値は表示されるので取り扱い注意)
$q = '{"query":"{ actor { apiAccess { keySearch(query: {types: INGEST, scope: {ingestTypes: LICENSE}}) { keys { name key ... on ApiAccessIngestKey { accountId } } } } } }"}'
Set-Content -Encoding ascii q.json $q
curl.exe -s -X POST https://api.newrelic.com/graphql -H "Content-Type: application/json" -H "API-Key: $env:NEWRELIC_API_KEY" --data-binary "@q.json"
```

アカウントのデータセンターが EU または日本(JP)の場合は `newrelic_region` も設定する(このアカウントは US)。

### 2. 有効化

```powershell
Copy-Item infra\terraform.tfvars.example infra\terraform.tfvars   # 初回のみ
# terraform.tfvars に newrelic_license_key = "..." を記入(git 管理外)
.\scripts\tf.ps1 apply
```

apply でタスク定義が更新され、web / cron が New Relic 付きの構成でローリング再起動する。イメージの再ビルドは不要。

### 3. 流れるデータ

| 種類 | 手段 | 内容 |
|---|---|---|
| APM | php-fpm / cron コンテナ内の PHP エージェント(`newrelic.framework=magento2`) | トランザクション、分散トレース、スロー SQL + EXPLAIN、エラー、外部呼び出し。アプリ名は `sunfish-magento-web` / `-cron` / `-install` |
| Logs in Context | PHP エージェントのログ転送(Monolog) | Magento の system/exception ログに trace.id / span.id を付与 |
| コンテナログ | FireLens(fluent-bit + newrelic 出力プラグイン) | nginx アクセスログ(JSON、traceparent 付き)、php-fpm、varnish、cron の標準出力。ECS メタデータ付き |
| Infrastructure | `newrelic/nri-ecs` サイドカー | Fargate タスク / コンテナ単位の CPU・メモリ・ネットワーク |
| AWS メトリクス | CloudWatch Metric Streams → Firehose → New Relic | ALB, ECS(Container Insights), RDS, ElastiCache, OpenSearch, EFS, NAT, Firehose |
| Browser(RUM) | PHP エージェントの自動注入 | ページ表示速度、Core Web Vitals、JS エラー |

### 4. 追加でおすすめの設定(手動)
- **AWS アカウント連携(IAM ロール)**: New Relic UI の Infrastructure → AWS → Add AWS account で "Metric Streams" 方式を選び、IAM ロールだけ作成する。Metric Streams 本体はこの Terraform が作成済みなので、タグやリソース名などのメタデータが補完される。
- **Magento New Relic Reporting モジュール**: 管理画面 Stores → Configuration → General → New Relic Reporting で有効化し、Account ID / Application ID / API キーを入れると、注文・顧客登録・管理者操作・cron・キャッシュフラッシュがカスタムイベントとして送られる。
- **Synthetics**: ストアフロント URL の Ping / Browser モニターを作成し、外形監視の訓練に使う。

## 運用

```powershell
# ECS のログ(FireLens 無効時はここに全ログ、有効時はサイドカーのログ)
aws logs tail /ecs/sunfish-test --follow --since 10m

# コンテナに入る(session-manager-plugin が必要)
aws ecs execute-command --cluster sunfish-test --task <task-id> --container php --interactive --command "/bin/bash"

# 夜間停止 / 朝再開(Fargate と RDS の課金を止める。OpenSearch / Valkey / NAT / ALB は継続)
.\scripts\scale.ps1 -Web 0 -Cron 0 -StopDb
.\scripts\scale.ps1 -Web 1 -Cron 1 -StartDb

# イメージ更新(Dockerfile 変更や Magento バージョン更新)
.\scripts\build-push.ps1 ; .\scripts\tf.ps1 apply ; .\scripts\run-install.ps1

# 全削除
.\scripts\tf.ps1 destroy
```

## 費用(概算、常時稼働、東京リージョン)

| リソース | 月額目安 (USD) |
|---|---|
| Fargate web (2 vCPU / 8 GB) | 105 |
| Fargate cron (1 vCPU / 4 GB) | 50 |
| RDS db.t4g.medium + ストレージ + PI | 80 |
| NAT Gateway | 45 + 転送量 |
| OpenSearch t3.small.search + EBS | 45 |
| ElastiCache cache.t4g.small | 40 |
| ALB | 25 |
| EFS / ECR / CloudWatch / SSM | 10 |
| **合計** | **約 400** |

使わない時間帯は `scale.ps1` で Fargate と RDS を止めると半分程度になる。

## 注意
- `.env` は `.gitignore` に追加したが、**初期コミットに AWS キーが含まれている**。`git rm --cached .env` で追跡を外し、キーをローテーションすることを推奨。
- Terraform の state は `infra/terraform.tfstate`(ローカル、git 管理外)。複数人で扱う場合は S3 バックエンドに移す。
- ALB は既定で全世界に公開(`alb_allowed_cidrs`)。オフィス IP に絞ることを推奨。
