# STL Viewer Web App

`STL-viewer.html` を中心にした、STLの表示・補正・保存を行うWebアプリです。

## 構成

- `server_app.py`
  - FastAPIベースのWebサーバー
- `STL-viewer.html`
  - ブラウザ側の本体
- `vendor/three/r128/`
  - Three.js のローカル配置
- `STL/`
  - サンプルSTLと、追加したモデルの保存先

## ローカル起動

1. `launch_stl_viewer.ps1` を実行します。
2. ブラウザで表示されたURLを開きます。

## Webサーバーへ配置する場合

このリポジトリの次のファイル・フォルダを、そのままサーバーへコピーすれば動かせます。

- `server_app.py`
- `STL-viewer.html`
- `index.html`
- `vendor/`
- `STL/`

サンプルSTLも `STL/` に入っています。

### Render で公開する場合

Render の Python Web Service として `render.yaml` を使うのが標準です。

- `render.yaml`
- `requirements.txt`
- `server_app.py`
- `STL-viewer.html`
- `vendor/`
- `STL/`

を使えば、同一ホストでフロントと API をまとめて公開できます。

永続化が必要なので、Render では `STORAGE_DIR` を永続ディスクに向けています。
もしディスクを付けない場合、STL のアップロード結果や状態は再デプロイで消えます。

## 配布用フォルダ

- `web_deploy/`
  - ローカル起動用スクリプトも含めた一式
- `web_deploy_prod/`
  - 本番Webサーバー用の最小構成
  - `server_app.py`
  - `STL-viewer.html`
  - `index.html`
  - `vendor/`
  - `STL/`
  - `README.md`
- `web_deploy_prod/`
  - 本番Webサーバー用の最小構成
  - `requirements.txt` / `render.yaml` 付き

## 生成されるファイル

- `web_state.json`
- `logs/`

これらは実行時に自動生成されます。
