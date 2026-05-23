# STL Viewer Web App

---

## 1. 目的

- STLファイルをブラウザで表示する
- モデルの位置・回転を調整する
- 調整結果をサーバー側に保存する
- Netlify + Python API の構成で公開する

---

## 2. 主な機能

- STLファイルの追加
- フォルダ一括読み込み
- サブディレクトリ込みの取り込み
- モデル一覧から選択
- 位置補正
- 回転補正
- 正面・平面・側面の向き補正
- 底面を土台に合わせる
- 透過WEBPで画像保存

---

## 3. アーキテクチャ

- フロントエンド
  - `STL-viewer.html`
  - Three.js をローカル同梱
- バックエンド
  - `server_app.py`
  - FastAPI で API を提供
- データ保存
  - `STL/`
  - `web_state.json`
- 公開先
  - Netlify: 静的フロント
  - Render: Python API + 永続ディスク

---

## 4. データフロー

1. ユーザーが STL を追加する
2. フロントが API に送る
3. サーバーが `STL/` に保存する
4. 一覧と選択状態が更新される
5. 位置・回転の補正値を保存する
6. 必要なら `WEBP` 画像として書き出す

---

## 5. 画面構成

- 左サイドバー
  - ファイル追加
  - 保存済み一覧
  - 表示設定
  - API接続
  - モデル補正
- 右側メイン
  - 3D表示
  - モデル情報
  - カメラ情報

---

## 6. AI / CLI 対応

- `stl_ai.ps1`
  - 一覧表示
  - 選択
  - 追加
  - 削除
  - 全削除
- `stl_ai.bat`
  - PowerShell ラッパー
- `launch_stl_viewer.ps1`
  - ローカル起動
  - ポート自動選択
  - API/画面起動

---

## 7. 公開構成

- Netlify
  - `netlify_deploy/`
  - 静的フロントのみ
  - `APIベースURL` を別ホストに向ける
- Render
  - `render.yaml`
  - Python Web Service
  - 永続ディスクで `STL/` を保持

---

## 8. 配布フォルダ

- `netlify_deploy/`
  - Netlify 向け静的配布
- `web_deploy_prod/`
  - Render / 本番向け最小構成
- `web_deploy/`
  - ローカル起動用スクリプト込み

---

## 9. 重要ファイル

- `STL-viewer.html`
- `server_app.py`
- `render.yaml`
- `requirements.txt`
- `netlify_deploy/`
- `web_deploy_prod/`

---

## 10. 運用上の注意

- Netlify には API がないので、そのままでは動かない
- API は Render など別ホストで動かす
- 永続化しないとアップロード済みSTLは再デプロイで消える
- `APIベースURL` は静的フロントから別ホストAPIへ向けるための設定

---

## 11. まとめ

- STL Viewer は「静的フロント + Python API」で構成
- Netlify はフロント公開
- Render は API と保存領域
- AI/CLI からも操作できるように設計済み

