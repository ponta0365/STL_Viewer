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

## 生成されるファイル

- `web_state.json`
- `logs/`

これらは実行時に自動生成されます。
