# Generates docs/architecture.svg from the official AWS Architecture Icons (July 2026 package).
# Usage: .\docs\build-architecture-svg.ps1 -IconDir <dir with the extracted *_48.svg / *_32.svg files>
# Labels use "|" as a line separator.
param(
    [Parameter(Mandatory = $true)][string]$IconDir,
    [string]$Out = (Join-Path $PSScriptRoot 'architecture.svg')
)
$ErrorActionPreference = 'Stop'
$font = "font-family=`"'Helvetica Neue',Arial,'Noto Sans JP','Yu Gothic UI','Meiryo',sans-serif`""
$sb = New-Object System.Text.StringBuilder

function Esc([string]$s) { return $s.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;') }

function IconData([string]$name) {
    $p = Join-Path $IconDir $name
    if (-not (Test-Path $p)) { throw "icon not found: $name" }
    $bytes = [System.IO.File]::ReadAllBytes($p)
    return 'data:image/svg+xml;base64,' + [Convert]::ToBase64String($bytes)
}

function Icon([string]$file, [double]$x, [double]$y, [double]$size = 48, [string]$label = '', [string]$sub = '', [double]$opacity = 1) {
    $href = IconData $file
    [void]$sb.AppendLine("<image x=`"$x`" y=`"$y`" width=`"$size`" height=`"$size`" opacity=`"$opacity`" href=`"$href`"/>")
    $cx = $x + $size / 2
    $ty = $y + $size + 14
    if ($label) {
        foreach ($l in ($label -split '\|')) {
            [void]$sb.AppendLine("<text x=`"$cx`" y=`"$ty`" text-anchor=`"middle`" font-size=`"11`" font-weight=`"600`" fill=`"#16191F`" $font>$(Esc $l)</text>")
            $ty += 13
        }
    }
    if ($sub) {
        foreach ($l in ($sub -split '\|')) {
            [void]$sb.AppendLine("<text x=`"$cx`" y=`"$ty`" text-anchor=`"middle`" font-size=`"9.5`" fill=`"#545B64`" $font>$(Esc $l)</text>")
            $ty += 12
        }
    }
}

function Frame([double]$x, [double]$y, [double]$w, [double]$h, [string]$icon, [string]$title, [string]$stroke, [string]$fill = 'none', [string]$dash = '', [string]$titleColor = '') {
    if (-not $titleColor) { $titleColor = $stroke }
    $d = ''
    if ($dash) { $d = "stroke-dasharray=`"$dash`"" }
    [void]$sb.AppendLine("<rect x=`"$x`" y=`"$y`" width=`"$w`" height=`"$h`" fill=`"$fill`" stroke=`"$stroke`" stroke-width=`"1.2`" $d/>")
    $tx = $x + 6
    if ($icon) {
        $href = IconData $icon
        [void]$sb.AppendLine("<image x=`"$x`" y=`"$y`" width=`"24`" height=`"24`" href=`"$href`"/>")
        $tx = $x + 30
    }
    [void]$sb.AppendLine("<text x=`"$tx`" y=`"$($y + 16)`" font-size=`"12`" font-weight=`"600`" fill=`"$titleColor`" $font>$(Esc $title)</text>")
}

function Txt([double]$x, [double]$y, [string]$s, [double]$size = 10.5, [string]$color = '#16191F', [string]$anchor = 'start', [string]$weight = 'normal') {
    foreach ($l in ($s -split '\|')) {
        [void]$sb.AppendLine("<text x=`"$x`" y=`"$y`" text-anchor=`"$anchor`" font-size=`"$size`" font-weight=`"$weight`" fill=`"$color`" $font>$(Esc $l)</text>")
        $y += $size * 1.25
    }
}

function Arrow([string]$points, [string]$color = '#16191F', [string]$dash = '', [string]$label = '', [double]$lx = 0, [double]$ly = 0, [string]$marker = 'end', [string]$anchor = 'start') {
    $d = ''
    if ($dash) { $d = "stroke-dasharray=`"$dash`"" }
    $m = ''
    if ($marker -match 'end') { $m += " marker-end=`"url(#arrow-$($color.TrimStart('#')))`"" }
    [void]$sb.AppendLine("<polyline points=`"$points`" fill=`"none`" stroke=`"$color`" stroke-width=`"1.4`" $d$m/>")
    if ($label) { Txt $lx $ly $label 9.5 $color $anchor }
}

function Box([double]$x, [double]$y, [double]$w, [double]$h, [string]$stroke, [string]$fill, [double]$r = 4, [string]$dash = '') {
    $d = ''
    if ($dash) { $d = "stroke-dasharray=`"$dash`"" }
    [void]$sb.AppendLine("<rect x=`"$x`" y=`"$y`" width=`"$w`" height=`"$h`" rx=`"$r`" fill=`"$fill`" stroke=`"$stroke`" stroke-width=`"1`" $d/>")
}

function SmallIcon([string]$file, [double]$x, [double]$y, [double]$size = 24) {
    $href = IconData $file
    [void]$sb.AppendLine("<image x=`"$x`" y=`"$y`" width=`"$size`" height=`"$size`" href=`"$href`"/>")
}

# ------------------------------------------------------------------ canvas
$W = 1760; $H = 1230
[void]$sb.AppendLine("<svg xmlns=`"http://www.w3.org/2000/svg`" xmlns:xlink=`"http://www.w3.org/1999/xlink`" width=`"$W`" height=`"$H`" viewBox=`"0 0 $W $H`">")
[void]$sb.AppendLine("<title>sunfish - Magento Open Source 2.4.9 on AWS ECS Fargate (final Terraform configuration)</title>")
[void]$sb.AppendLine('<defs>')
foreach ($c in @('16191F', '0972D3', '545B64', '1CE783')) {
    [void]$sb.AppendLine("<marker id=`"arrow-$c`" viewBox=`"0 0 10 10`" refX=`"9`" refY=`"5`" markerWidth=`"7`" markerHeight=`"7`" orient=`"auto-start-reverse`"><path d=`"M0,0 L10,5 L0,10 z`" fill=`"#$c`"/></marker>")
}
[void]$sb.AppendLine('</defs>')
[void]$sb.AppendLine("<rect width=`"$W`" height=`"$H`" fill=`"#FFFFFF`"/>")

# title
Txt 24 34 'sunfish: Magento Open Source 2.4.9 (Adobe Commerce 無料版) テスト環境  -  AWS 構成図 (Terraform 最終構成)' 18 '#16191F' 'start' '700'
Txt 24 54 'https://actest.examp1e.site/  /  ECS Fargate + RDS MySQL 8.4 + ElastiCache Valkey 9 + OpenSearch 3 + EFS  /  AWS WAF  /  New Relic 連携   (2026-09-27, AWS Architecture Icons 2026-07)' 11.5 '#545B64'

# ------------------------------------------------------------------ users (left)
[void]$sb.AppendLine('<g transform="translate(60,470)"><circle cx="24" cy="14" r="11" fill="#232F3E"/><path d="M2,52 C2,32 46,32 46,52 Z" fill="#232F3E"/></g>')
Txt 84 540 '利用者 / ブラウザ' 11 '#16191F' 'middle' '600'
Txt 84 553 'https://actest.examp1e.site/' 9.5 '#545B64' 'middle'
Txt 84 565 'New Relic Browser エージェント|自動注入 (RUM)' 9 '#545B64' 'middle'

# ------------------------------------------------------------------ AWS cloud / region
Frame 190 80 1250 1120 'AWS-Cloud_32.svg' 'AWS Cloud  (account 337257207190)' '#242F3E'
Frame 210 116 1210 1064 'Region_32.svg' 'Region ap-northeast-1 (東京)' '#00A4A6' 'none' '6,4'

# edge services (left column inside region)
Icon 'Arch_Amazon-Route-53_48.svg' 250 175 48 'Route 53' 'hosted zone examp1e.site|A (alias) actest → ALB'
Icon 'Arch_AWS-Certificate-Manager_48.svg' 250 300 48 'ACM 証明書' 'actest.examp1e.site|DNS 検証 (Route 53)'
Icon 'Arch_AWS-WAF_48.svg' 250 430 48 'AWS WAF (regional)' 'IP reputation / Common|KnownBadInputs / SQLi|rate limit 3000 req/5min'
Icon 'Res_Amazon-CloudWatch_Logs_48.svg' 250 570 48 'WAF ログ' 'aws-waf-logs-sunfish-test|(BLOCK / COUNT のみ)' 0.9

# ------------------------------------------------------------------ VPC
Frame 370 150 1000 700 'Virtual-private-cloud-VPC_32.svg' 'VPC sunfish-test  10.60.0.0/16' '#8C4FFF'
Icon 'Res_Amazon-VPC_Internet-Gateway_48.svg' 346 470 48 'Internet|Gateway'

# ALB (logical, spans both AZs) at the top of the VPC
Icon 'Res_Elastic-Load-Balancing_Application-Load-Balancer_48.svg' 640 178 48
Txt 700 194 'Application Load Balancer  sunfish-test' 11.5 '#16191F' 'start' '700'
Txt 700 208 ':443 HTTPS (TLS 1.3, ACM 証明書)   :80 → 443 リダイレクト   WAF 適用' 9.5 '#545B64'
Txt 700 221 'ターゲット: web タスクの varnish:80 (IP ターゲット)   ヘルスチェック /health_check.php' 9.5 '#545B64'
Txt 700 234 'ノードは両 AZ の public subnet に配置' 9.5 '#545B64'

# AZ columns
Frame 400 240 470 600 '' 'Availability Zone ap-northeast-1c' '#00A4A6' 'none' '4,3' '#545B64'
Frame 890 240 460 600 '' 'Availability Zone ap-northeast-1d' '#00A4A6' 'none' '4,3' '#545B64'

# public subnets
Frame 415 270 440 100 'Public-subnet_32.svg' 'Public subnet 10.60.0.0/24' '#7AA116' '#F2F6E8'
Frame 905 270 430 100 'Public-subnet_32.svg' 'Public subnet 10.60.1.0/24' '#7AA116' '#F2F6E8'
Icon 'Res_Elastic-Load-Balancing_Application-Load-Balancer_48.svg' 640 292 48 '' '' 0.45
Txt 664 356 'ALB ノード' 9.5 '#545B64' 'middle'
Icon 'Res_Elastic-Load-Balancing_Application-Load-Balancer_48.svg' 1100 292 48 '' '' 0.45
Txt 1124 356 'ALB ノード' 9.5 '#545B64' 'middle'
Icon 'Res_Amazon-VPC_NAT-Gateway_48.svg' 780 292 48 'NAT Gateway' '(egress)'

# app private subnets
Frame 415 390 440 270 'Private-subnet_32.svg' 'Private subnet (app) 10.60.10.0/24' '#00A4A6' '#E6F6F7'
Frame 905 390 430 270 'Private-subnet_32.svg' 'Private subnet (app) 10.60.11.0/24' '#00A4A6' '#E6F6F7'

# ECS cluster spanning both app subnets
Box 425 418 900 232 '#ED7100' 'none' 4 '5,3'
SmallIcon 'Arch_Amazon-Elastic-Container-Service_48.svg' 425 418 24
Txt 455 434 'ECS cluster sunfish-test  (AWS Fargate, Container Insights 有効, ECS Exec 有効)' 12 '#ED7100' 'start' '600'
SmallIcon 'Arch_AWS-Fargate_48.svg' 1290 420 28

# web task
Box 450 448 400 108 '#ED7100' '#FFFFFF' 4
Txt 460 463 'service "web"  -  task 2 vCPU / 8 GB' 11 '#16191F' 'start' '700'
Icon 'Res_Amazon-Elastic-Container-Service_Container-1_48.svg' 462 472 40 'varnish' ':80 FPC'
Icon 'Res_Amazon-Elastic-Container-Service_Container-2_48.svg' 542 472 40 'nginx' ':8080'
Icon 'Res_Amazon-Elastic-Container-Service_Container-3_48.svg' 622 472 40 'php-fpm 8.4' 'Magento 2.4.9|+ NR PHP agent'
Arrow '503,492 541,492' '#16191F'
Arrow '583,492 621,492' '#16191F'
Box 710 472 132 74 '#1CE783' '#F3FDF7' 3 '3,2'
Txt 716 485 'New Relic sidecars' 9.5 '#0B6B3A' 'start' '700'
Txt 716 498 '• log_router (FireLens,|  fluent-bit → NR Logs)|• newrelic-infra (nri-ecs)' 9 '#16191F'
Txt 716 540 '※ ライセンスキー設定時のみ' 8.5 '#545B64'

# EFS mount target (AZ c)
Icon 'Res_Amazon-Elastic-File-System_File-System_48.svg' 690 592 40 'EFS mount target' 'pub/media (access point uid 33)'

# cron task + install task (AZ d)
Box 925 448 190 100 '#ED7100' '#FFFFFF' 4
Txt 935 463 'service "cron"  1 vCPU / 4 GB' 11 '#16191F' 'start' '700'
Icon 'Res_Amazon-Elastic-Container-Service_Task_48.svg' 940 472 40 'php (cron)' 'cron:run 60s ループ + キュー'
Txt 995 490 '+ NR sidecars' 9 '#0B6B3A'
Box 1130 448 195 100 '#ED7100' '#FFFFFF' 4 '4,3'
Txt 1140 463 'task "install" (手動・一回限り)' 11 '#16191F' 'start' '700'
Icon 'Res_Amazon-Elastic-Container-Service_Task_48.svg' 1145 472 40 'php (install)' 'setup:install / upgrade, reindex'
Icon 'Res_Amazon-Elastic-File-System_File-System_48.svg' 1230 592 40 'EFS mount target' 'pub/media'
Txt 930 560 'サービスのタスクは両 AZ の app subnet に配置される|(desired 1 のときはどちらか一方)。' 9 '#545B64'

# data private subnets
Frame 415 680 440 150 'Private-subnet_32.svg' 'Private subnet (data) 10.60.20.0/24' '#00A4A6' '#E6F6F7'
Frame 905 680 430 150 'Private-subnet_32.svg' 'Private subnet (data) 10.60.21.0/24' '#00A4A6' '#E6F6F7'
Icon 'Arch_Amazon-RDS_48.svg' 435 700 48 'RDS MySQL 8.4' 'db.t4g.medium, gp3 20GB|拡張モニタリング + PI|slow / error log'
Icon 'Res_Amazon-ElastiCache_ElastiCache-for-Valkey_48.svg' 610 700 48 'ElastiCache Valkey 9.1' 'cache.t4g.small ×1|db0 cache / db1 FPC / db2 session'
Icon 'Arch_Amazon-OpenSearch-Service_48.svg' 760 700 48 'OpenSearch 3.3' 't3.small.search ×1, gp3 20GB|HTTPS, VPC アクセスのみ'
Txt 1120 735 'サブネットグループの 2 番目の AZ' 10 '#545B64' 'middle'
Txt 1120 750 '(RDS Multi-AZ / Valkey レプリカ / OpenSearch ゾーン分散は OFF)|db_multi_az = true で RDS スタンバイをここに配置' 9.5 '#545B64' 'middle'

# S3 gateway endpoint on VPC edge
Box 895 838 235 22 '#8C4FFF' '#FFFFFF' 3
Txt 1012 853 'S3 Gateway VPC Endpoint (ECR レイヤー取得を NAT から外す)' 8.5 '#8C4FFF' 'middle'

# ------------------------------------------------------------------ region services below VPC
Frame 370 880 1000 290 '' 'リージョンサービス (VPC 外)' '#545B64' 'none' '2,3'
Icon 'Arch_Amazon-Elastic-Container-Registry_48.svg' 400 912 48 'ECR' 'sunfish/magento|sunfish/varnish|(ローカル Docker で build / push)'
Icon 'Res_AWS-Systems-Manager_Parameter-Store_48.svg' 560 912 48 'SSM Parameter Store' 'SecureString: DB パスワード,|crypt key, admin パスワード,|New Relic ライセンスキー'
Icon 'Res_Amazon-CloudWatch_Logs_48.svg' 720 912 48 'CloudWatch Logs' '/ecs/sunfish-test|RDS slow / error, WAF'
Icon 'Arch_Amazon-CloudWatch_48.svg' 860 912 48 'CloudWatch Metric Streams' 'ALB, WAF, ECS, RDS,|ElastiCache, OpenSearch,|EFS, NAT (OTel 1.0)'
Icon 'Arch_Amazon-Data-Firehose_48.svg' 1020 912 48 'Data Firehose' 'HTTP endpoint →|New Relic (1 MB / 60 s)'
Icon 'Res_Amazon-Simple-Storage-Service_Bucket_48.svg' 1160 912 48 'S3' '配信失敗データの|バックアップ'
Txt 400 1090 'Terraform 管理 (infra/): VPC / ALB / WAF / ACM / Route 53 / ECS / ECR / EFS / RDS / ElastiCache / OpenSearch / SSM / CloudWatch / Metric Streams / Firehose / IAM。|Metric Streams・Firehose・FireLens・nri-ecs は newrelic_license_key を設定した apply で有効化 (イメージの再ビルド不要)。|Fargate タスクは task role で EFS (IAM 認可) と ECS Exec、execution role で ECR pull・CloudWatch Logs・SSM 秘密情報の取得を行う。|web タスク内: 3 コンテナは localhost で連携 (varnish:80 → nginx:8080 → php-fpm:9000)。env.php は起動時に環境変数 + SSM の秘密情報から生成。|Magento からの FPC パージは同一タスクの Varnish (localhost) へ。ログは stdout → FireLens (New Relic) または CloudWatch Logs。' 9.5 '#545B64'

# ------------------------------------------------------------------ New Relic (SaaS, right)
Box 1470 300 265 430 '#1CE783' '#F3FDF7' 6
Txt 1602 325 'New Relic (SaaS)' 14 '#0B6B3A' 'middle' '700'
Txt 1602 341 'US / EU / JP データセンター' 9.5 '#545B64' 'middle'
$nrItems = @(
    @('APM', 'PHP エージェント: トランザクション, 分散トレース,|スロー SQL + EXPLAIN, エラー, コードレベル指標'),
    @('Logs in Context', 'Monolog → trace.id / span.id 付き'),
    @('Logs (FireLens)', 'nginx JSON アクセスログ, php-fpm, varnish, cron'),
    @('Infrastructure (ECS / Fargate)', 'nri-ecs: タスク / コンテナの CPU・メモリ・NW'),
    @('AWS Metrics', 'CloudWatch Metric Streams 経由 (ALB, WAF, RDS ...)'),
    @('Browser (RUM)', '自動注入: Core Web Vitals, JS エラー')
)
$yy = 362
foreach ($it in $nrItems) {
    Box 1485 $yy 235 50 '#1CE783' '#FFFFFF' 3
    Txt 1493 ($yy + 14) $it[0] 10.5 '#0B6B3A' 'start' '700'
    Txt 1493 ($yy + 27) $it[1] 8.5 '#16191F'
    $yy += 58
}
Txt 1602 722 '(Synthetics / アラート / Magento NR Reporting は手動設定)' 8.5 '#545B64' 'middle'

# ------------------------------------------------------------------ arrows
# users -> route53 (dns), users -> waf -> igw -> alb node
Arrow '108,470 108,215 250,215' '#545B64' '4,3' 'DNS 名前解決' 120 208
Arrow '132,494 200,494 200,454 250,454' '#0972D3' '' 'HTTPS :443' 140 488
Arrow '298,454 322,454 322,494 346,494' '#0972D3'
Arrow '394,494 405,494 405,316 640,316' '#0972D3' '' 'ALB へ' 410 312
# route53 alias / acm cert -> alb
Arrow '298,199 640,199' '#545B64' '4,3' 'A alias' 470 195
Arrow '298,324 330,324 330,214 640,214' '#545B64' '4,3' '証明書 (TLS 終端)' 470 229
# waf -> waf log
Arrow '274,478 274,570' '#545B64' '4,3'
# alb node -> varnish (enters from the left of the task box)
Arrow '664,340 664,380 442,380 442,492 462,492' '#0972D3' '' ':80 → varnish' 480 377

# php -> data stores (leave from the bottom edge of the task box)
Arrow '622,556 622,580 459,580 459,700' '#16191F' '' 'MySQL 3306' 465 640
Arrow '634,556 634,700' '#16191F' '' 'Valkey 6379' 640 676
Arrow '646,556 646,580 784,580 784,700' '#16191F' '' 'OpenSearch 443' 790 640
# php -> efs
Arrow '672,556 672,570 710,570 710,592' '#16191F' '' 'NFS' 716 568
# cron -> data layer
Arrow '960,548 960,724 808,724' '#16191F' '' 'cron も同じデータ層へ' 966 600
# task egress via nat
Arrow '804,448 804,400 840,400 840,316 828,316' '#545B64' '4,3' 'NAT 経由 egress|(Docker Hub, New Relic)' 846 380
# ecr image pull (via s3 endpoint) into the app subnet
Arrow '424,936 340,936 340,655 415,655' '#545B64' '4,3' 'image pull' 344 648
# ssm secrets injected into tasks
Arrow '584,912 584,868 535,868 535,556' '#545B64' '4,3' 'secrets 注入' 540 866
# container logs -> cloudwatch logs (route through the gap between the AZs)
Arrow '744,912 744,868 880,868 880,520 850,520' '#545B64' '4,3' 'awslogs' 884 600
# rds logs -> cloudwatch logs
Arrow '483,730 550,730 550,815 744,815 744,912' '#545B64' '4,3' 'slow / error log' 556 812
# metric stream -> firehose -> nr / s3
Arrow '908,936 1020,936' '#1CE783' '' 'stream' 950 930
Arrow '1068,936 1160,936' '#545B64' '4,3' 'failed only' 1090 930
Arrow '1044,912 1044,862 1455,862 1455,620 1470,620' '#1CE783' '' 'AWS metrics → New Relic' 1160 858
# nr agents -> nr (from the sidecar box top, above the task boxes)
Arrow '776,472 776,442 1340,442 1340,400 1470,400' '#1CE783' '' 'APM / Logs / Infra  (HTTPS, NAT 経由)' 1000 439
Arrow '1020,448 1020,442' '#1CE783' '' '' 0 0 'none'
# browser rum
Arrow '132,540 150,540 150,1215 1602,1215 1602,730' '#1CE783' '4,3' 'Browser (RUM) beacon' 900 1210

# legend
Box 1470 780 265 110 '#545B64' '#FFFFFF' 4
Txt 1480 796 '凡例' 11 '#16191F' 'start' '700'
Arrow '1480,812 1520,812' '#0972D3'
Txt 1528 815 '利用者リクエスト (HTTPS)' 9.5
Arrow '1480,832 1520,832' '#16191F'
Txt 1528 835 'アプリ ↔ データ層の通信' 9.5
Arrow '1480,852 1520,852' '#545B64' '4,3'
Txt 1528 855 '制御・設定・ログ (AWS 内)' 9.5
Arrow '1480,872 1520,872' '#1CE783'
Txt 1528 875 'New Relic へのテレメトリ' 9.5

[void]$sb.AppendLine('</svg>')
[System.IO.File]::WriteAllText($Out, $sb.ToString(), (New-Object System.Text.UTF8Encoding($false)))
Write-Host "wrote $Out ($([math]::Round((Get-Item $Out).Length/1KB)) KB)"
