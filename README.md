# chromium-builder

Create a docker image for the Chromium develop envrionment.\

## Install

Add `bin` directory into PATH in the profile such as `.bashrc`.

```sh
export PATH="/path/to/chromium-builder/bin:$PATH"
```

## Requirements

rootless Docker を前提とします。rootless Docker ではコンテナの root がホストユーザーに対応するため、コンテナ内で作成したファイルはホストユーザーの所有になります。

rootful Docker では、コンテナの root が作成したファイルはホストの root 所有になり、ホストユーザーは書き込めません。`cr-exec-env` は `--username` が無いと警告します。`--username` を付けるとホストと同じ UID/GID のユーザーとして実行しますが、`cr-fetch-src` などが作成した `src` は root 所有のままなので、事前に所有者を変更してください。

```sh
sudo chown -R "$(id -u):$(id -g)" ~/work/chromium
cd ~/work/chromium
cr-exec-env --username developer
```

userns-remap を有効にした Docker には対応していません。

Docker 20.10 以降が必要です (`docker run --pull=never` を使用します)。

## scripts

イメージは2段階で作成します。base イメージは Chromium のバージョンに依存せず、ビルド用イメージは取得したソースに合わせて作成します。

#### cr-setup-base-docker-image

- base イメージ `env-chromium/focal:v1` を作ります。`cr-fetch-src` と `cr-setup-builder-docker-image` に必要です。
- `--no-cache`: Docker のキャッシュを使わない。
- `--apt <url>`, `--apt-country <country>`: apt リポジトリを指定する。

#### cr-fetch-src

- Chromium ソースコードを `--dest` のディレクトリにフェッチします。`--dest` は必須です。
- `--cr <major>`: `lib/checkout_list.txt` からメジャーバージョンに対応するタグを選ぶ。`HEAD` も指定できる。
- `--chromium <tag>`: フルタグ (e.g. `120.0.6099.234`) を指定する。
- `--full-history`: 全履歴を取得する。既定では直近のコミットのみを取得します。
- 途中で失敗した場合は、同じ引数で再実行すると `gclient sync` から再開します。
  - 再開では取得済みの `src` を更新しません。別のタグを指定するとエラーになり、`--cr HEAD` では既存の `src` をそのまま使います。
  - 履歴の深さは変更できません。既定で取得した `src` に `--full-history` を指定するとエラーになるので、`src` を削除してください。

#### cr-setup-builder-docker-image

- `--cr-dir` のソースの依存をインストールし、ビルド用イメージ `env-chromium-build/focal-<version>:v1` を作ります。
  - `--cr-dir` とは Chromium リポジトリの `src` の親ディレクトリにある作業ディレクトリを指定します。`.gclient` 等が配置されています。
- Deemed to agree to the EULA.
- `--gclient-sync`: `gclient runhooks` の代わりに `gclient sync` を実行する。

#### cr-exec-env

- `cr-setup-builder-docker-image` で作成したイメージのコンテナを作成し、カレントディレクトリを `/mnt/work` にマウントします。
- カレントディレクトリは Chromium ソースコードの `src` ディレクトリの親ディレクトリでなければなりません。
- `--image <name:tag>`: 使用するイメージを指定する。
- `--img <prefix>`: `<コードネーム>-<バージョン>` の前方一致でビルド用イメージを選ぶ (e.g. `focal-132`)。バージョンは `.` 区切りの単位で比較します。複数候補がある場合は最新バージョンを使います。`--image` とは併用できません。
- `--gpu-all`: コンテナに全 GPU を割り当てる。
- `--xephyr <width>x<height>`: Xephyr を起動して使用する。
- `--username <name>`: rootful Docker 向けのオプションです。rootless Docker ではエラーになります。ホストのファイルの所有者は変更しません。
- `-- <command> [args...]`: シェルの代わりにコマンドを実行する。引数はそのままコンテナへ渡します。`&&` やリダイレクトを使う場合は `-- bash -c 'cd src && autoninja -C out/release chrome'` のように指定します。

## Tests

```sh
for test in tests/test-*.sh; do bash "$test"; done
```

## Hands on

### basic

ベースとなる Docker image を作成する。

```sh
cr-setup-base-docker-image --apt-country jp --no-cache
```

Chromium リポジトリを取得する。

```sh
cr-fetch-src --cr 132 --dest ~/work/chromium
```

リポジトリからビルド用 Docker image を作成する。Docker image の名前は `chrome/VERSION` を参照する。

```sh
cr-setup-builder-docker-image --cr-dir ~/work/chromium
```

作成したビルド用 Docker image から Docker container に入り、 Chromium をビルドする。

```sh
cd ~/work/chromium
cr-exec-env

# In the docker container
cd src
mkdir -p out/release
cd out/release
echo 'is_debug=false' > args.gn
gn gen .
autoninja content_shell

exit
```

Chromium を起動する。

```sh
cd ~/work/chromium/src/out/release
./content_shell https://example.com
```

vscode による開発環境を整備する。(clangd extensions are required)

```sh
cd ~/work/chromium/src/
cp -r tools/vscode .vscode
tools/clang/scripts/generate_compdb.py -p out/release > compile_commands.json
```
