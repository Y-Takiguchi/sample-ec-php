# sample-ec-php

Claude Code研修用のサンプルリポジトリです。小規模ECサイトの管理システム
（商品管理・注文管理・在庫管理）を題材に、「注文すると在庫が減る」という
業務ロジックを中心に構成しています。

## 1. 構成図

```
┌────────────────┐        ┌──────────────────────┐
│   ブラウザ      │        │        Nginx          │  :8080
│ (Vue3 SPA)      │──────▶│  /api/*  → PHP-FPM     │
└────────────────┘        │  /*      → Vite(5173)  │
                           └──────────┬────────────┘
                                      │
                    ┌─────────────────┼─────────────────┐
                    ▼                                    ▼
          ┌───────────────────┐              ┌───────────────────┐
          │  frontend (Vite)   │              │  php (CodeIgniter4) │
          │  Vue3 / Pinia /     │              │  REST API            │
          │  vue-router         │              │  PHP 8.3 / PHP-FPM   │
          └───────────────────┘              └──────────┬──────────┘
                                                          │
                                                          ▼
                                              ┌───────────────────┐
                                              │   db (PostgreSQL16) │
                                              └───────────────────┘
```

- **frontend**: Vue 3 (Composition API) + Vite。商品一覧・詳細、カート、注文一覧・詳細画面を提供するSPA。
- **php**: CodeIgniter 4によるREST API。JSONを返却し、画面描画は行わない。
- **nginx**: `/api/*` をPHP-FPMへ、それ以外をVite dev serverへ振り分けるリバースプロキシ。
- **db**: PostgreSQL 16。

## 2. ディレクトリ構成

```
project/
├── docker-compose.yml
├── docker/                 ← Dockerfile / nginx設定
├── backend/                ← CodeIgniter 4 (REST API)
├── frontend/                ← Vue 3 (SPA)
├── db/                      ← トリガー・ストアドプロシージャ・手動運用用プロシージャ・大量データ投入用SQL
└── docs/                    ← 補助ドキュメント
```

## 3. dockerを使ったセットアップ

### 3.1. 環境変数ファイルの準備

各ディレクトリで `.env.example` をコピーして `.env` として使ってください。

```bash
cp backend/.env.example backend/.env
cp frontend/.env.example frontend/.env
```

`backend/.env` にはDB接続情報とダミーのAPIキー（`app.externalApiKey`）が含まれています。
`.env` はどちらのディレクトリでも `.gitignore` により追跡対象外です。実際の秘匿情報は
`.env.example` のようにリポジトリへコミットしないでください。

### 3.2. Docker Composeで起動

```bash
docker compose build
docker compose up -d
```

起動するコンテナ:

| サービス   | 役割                    | ポート                                                                  |
| ---------- | ----------------------- | ----------------------------------------------------------------------- |
| `nginx`    | リバースプロキシ        | http://localhost:8080                                                   |
| `php`      | CodeIgniter 4 (PHP-FPM) | (nginx経由)                                                             |
| `frontend` | Vite dev server         | http://localhost:5173（nginx経由でも http://localhost:8080 から到達可） |
| `db`       | PostgreSQL 16           | localhost:5432                                                          |

> **注意（改行コードについて）**: Windows環境でGitの`core.autocrlf`が有効な場合など、
> `git checkout`時に`docker/php/entrypoint.sh`の改行コードがLFからCRLFに変換されて
> しまうことがあります。この状態で`php`コンテナを起動すると、シバン行（`#!/bin/sh`）が
> 正しく解釈されずに `no such file or directory` のようなエラーでコンテナが起動に
> 失敗します。その場合は`entrypoint.sh`の改行コードをLFに変更してから
> `docker compose up -d`（またはビルドし直し）を行ってください。

### 3.3. バックエンド: マイグレーション・シーディング

```bash
docker compose exec php php spark migrate
docker compose exec php php spark db:seed DatabaseSeeder
```

- `php spark migrate:status` で適用状況を確認できます。
- `php spark migrate:refresh` でDBを作り直せます（データは消えます）。

### 3.4. フロントエンド: 依存インストール・起動

Docker Compose起動時に `frontend` コンテナが自動で `npm run dev` を実行しますが、
ローカルで直接操作したい場合は以下を利用してください。

```bash
cd frontend
npm install
npm run dev
```

ブラウザで **http://localhost:8080**（nginx経由）を開いてください。こちらがメインの
アクセス先です。

`http://localhost:5173`（Vite dev serverに直接）にも一応アクセスできますが、
nginxを経由しないため`/api`宛のリクエストがバックエンドまで届かず、APIが正しく
取得できません（`frontend/.env`の`VITE_API_BASE_URL=/api`は相対パスで、nginxの
振り分けを前提にしているため）。動作確認は必ず8080番で行ってください。

## 4. Dockerを使わないセットアップ

Dockerを使わず、PostgreSQL・PHP・Node.jsをローカルに直接インストールして
動かす場合の手順です。あらかじめ以下をローカル環境に用意してください。

- PostgreSQL 16（近いメジャーバージョンであれば概ね動作します）
- PHP 8.3（拡張: `pdo_pgsql` `pgsql` `intl` `zip` `mbstring` `curl`）
- Composer
- Node.js 20以上

### 4.1. データベースの準備

PostgreSQLサーバーを起動し、DBを作成します。

```bash
psql -U postgres -h localhost -c "CREATE DATABASE sample_ec;"
psql -U postgres -h localhost -c "CREATE DATABASE sample_ec_test;"
```

### 4.2. 環境変数ファイルの準備

上記「環境変数ファイルの準備」と同様に `.env` を用意したうえで、
`backend/.env` を以下のように編集してください（Docker利用時は `db` という
コンテナ名で名前解決していたものを、ローカルのPostgreSQLに向け直します）。

```
database.default.hostname = localhost
database.tests.hostname = localhost
app.baseURL = 'http://localhost:8888/'
```

`database.default.username` / `password` は、ローカルPostgreSQLの実際の
認証情報に合わせて変更してください。

`frontend/.env` は、nginxを経由しないためバックエンドへの絶対URLに変更します。

```
VITE_API_BASE_URL=http://localhost:8888/api
```

### 4.3. バックエンド: 依存インストール・マイグレーション・起動

```bash
cd backend
composer install
php spark migrate
php spark db:seed DatabaseSeeder
php spark serve --host localhost --port 8888
```

`php spark serve` はCodeIgniter4組み込みの開発用サーバーで、nginx/PHP-FPMの
代わりになります。ポート番号は空いていれば任意で構いません。

### 4.4. フロントエンド: 依存インストール・起動

```bash
cd frontend
npm install
npm run dev
```

`backend/app/Config/Cors.php` は既定で `http://localhost:5173` を許可して
いるため、追加設定なしでフロントエンドからAPIを呼び出せます。

### 4.5. アクセス

ブラウザで http://localhost:5173 を開いてください（nginxを経由しないため、
8080番ではなくこちらが入口になります）。

## 5. テストの実行方法

アプリ固有のテストコードは、研修のテスト実装章で受講者が追加する想定のため
未実装です。テストフレームワーク自体は導入済みなので、以下のコマンドで
すぐにテストを書き始められます。

### 5.1. バックエンド（PHPUnit）

初回のみ、テスト用DB（`sample_ec_test`）を作成してください。

```bash
docker compose exec db psql -U postgres -c "CREATE DATABASE sample_ec_test;"
```

```bash
docker compose exec php vendor/bin/phpunit
```

（Dockerを使わない場合は、`backend`ディレクトリで直接 `vendor/bin/phpunit` を
実行してください。）

CodeIgniter 4標準の`CIUnitTestCase` / `FeatureTestTrait` / `DatabaseTestTrait`が
利用できます。`backend/tests/` 配下にテストクラスを追加してください
（`php spark make:test` でひな形を生成できます）。

### 5.2. フロントエンド（Vitest）

```bash
cd frontend
npm run test
```

`frontend/vite.config.js` にVitestの設定（`jsdom`環境）を用意済みです。
`frontend/tests/` 配下に `*.spec.js` を追加してください。
（テストファイルが1つもない状態で `npm run test` を実行すると
"No test files found" で終了コード1になりますが、これは想定通りの挙動です。）

## 6. APIエンドポイント一覧

| Method | Path                 | 概要                               |
| ------ | -------------------- | ---------------------------------- |
| GET    | `/api/products`      | 商品一覧取得                       |
| GET    | `/api/products/{id}` | 商品詳細取得                       |
| GET    | `/api/orders`        | 注文一覧取得                       |
| GET    | `/api/orders/{id}`   | 注文詳細取得（明細付き）           |
| POST   | `/api/orders`        | 注文作成（複数商品まとめて注文可） |

管理者向け（`/api/admin/*`）:

| Method | Path                                       | 概要                                   |
| ------ | ------------------------------------------- | -------------------------------------- |
| POST   | `/api/admin/products/{id}/receive-stock`    | 仕入れによる在庫増加を登録             |
| PATCH  | `/api/admin/products/{id}/discount`         | 商品の割引率（%）を設定・解除          |

`POST /api/orders` のリクエストボディ例:

```json
{
  "customer_id": 1,
  "items": [
    { "product_id": 1, "quantity": 2 },
    { "product_id": 3, "quantity": 1 }
  ]
}
```

CORSは `backend/app/Config/Cors.php` で許可オリジンを管理しています
（デフォルトではVite dev serverの `http://localhost:5173` を許可）。

## 7. PL/pgSQL（トリガー・ストアドプロシージャ）

`db/triggers.sql` に、注文明細(`order_items`)へのINSERTをきっかけに
`products.stock` を自動減算し `stock_logs` に記録するトリガー関数と、
複数明細をまとめて登録する（在庫チェック付きの）ストアドプロシージャ
`sp_create_order` を用意しています。

これはAPI（PHP側）の業務ロジックとは独立したデモ用の実装です。
APIは既にPHP側で在庫チェック・在庫減算を行っているため、このトリガーを
適用した状態でAPI経由の注文を行うと在庫が二重に減算される点に注意してください。

適用方法:

```bash
docker compose exec -T db psql -U postgres -d sample_ec -f - < db/triggers.sql
```

ストアドプロシージャの呼び出し例:

```bash
docker compose exec db psql -U postgres -d sample_ec -c \
  "CALL sp_create_order(1, '[{\"product_id\": 1, \"quantity\": 2}]'::jsonb);"
```

### 7.1. 大量データ投入（検索パフォーマンス改善デモ用）

`db/seed_large_data.sql` は `stock_logs` に10万件のダミーデータを投入する
スクリプトです。自動実行はされないため、手動で実行してください。

```bash
docker compose exec -T db psql -U postgres -d sample_ec -f - < db/seed_large_data.sql
```

### 7.2. 手動運用用プロシージャ（在庫操作・新規登録）

`db/admin_procedures.sql` に、管理画面・APIを経由せずにDBを直接操作するための
ストアドプロシージャを用意しています。トリガーは作成しないため、
`db/triggers.sql` と異なりAPI経由の注文と併用しても在庫が二重に減算されることはありません。

適用方法（初回のみ。`migrate:refresh` 等でDBを作り直した場合は再度適用してください）:

```bash
docker compose exec -T db psql -U postgres -d sample_ec -f - < db/admin_procedures.sql
```

| プロシージャ | 用途 | `stock_logs.reason` |
|---|---|---|
| `sp_register_product(商品名, 価格[, 在庫, カテゴリ, 割引率])` | 商品の新規登録 | `initial`（初期在庫が1以上の場合のみ記録） |
| `sp_receive_stock(商品ID, 数量)` | 仕入れ（入荷）登録 | `purchase` |
| `sp_adjust_stock(商品ID, 増減数[, 理由])` | 棚卸差異・破損・返品などの在庫調整 | 指定した理由（省略時は `adjustment`） |
| `sp_register_customer(氏名, メールアドレス)` | 顧客の新規登録 | - |

`[ ]` 内の引数は省略可能です。

呼び出し例:

```bash
# 商品の新規登録（在庫30個、割引なし）
docker compose exec db psql -U postgres -d sample_ec -c \
  "CALL sp_register_product('ワイヤレス充電器', 3280, 30, 'PCアクセサリ');"

# 商品ID=7 を20個入荷
docker compose exec db psql -U postgres -d sample_ec -c "CALL sp_receive_stock(7, 20);"

# 商品ID=7 を破損で3個減らす / 返品で1個戻す
docker compose exec db psql -U postgres -d sample_ec -c "CALL sp_adjust_stock(7, -3);"
docker compose exec db psql -U postgres -d sample_ec -c "CALL sp_adjust_stock(7, 1, 'return');"

# 顧客の新規登録
docker compose exec db psql -U postgres -d sample_ec -c \
  "CALL sp_register_customer('山田 花子', 'hanako@example.com');"
```

実行結果は `NOTICE: 入荷を登録しました（商品ID: 7, 在庫: 12 → 32）` のように表示されます。
存在しない商品ID、0以下の入荷数量、調整後の在庫がマイナスになる操作、登録済みのメールアドレスなど
不正な入力の場合はエラーで中断され、その呼び出しによる変更はすべてロールバックされます。
