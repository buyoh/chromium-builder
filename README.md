# chromium-builder

Create a docker image for the Chromium develop envrionment.\

## Limitations

- Supports only `120.0.6099.234`.

## Install

Add `bin` directory into PATH in the profile such as `.bashrc`.

```sh
export PATH="/path/to/chromium-builder/bin:$PATH"
```

## scripts

### -

#### cr-setup-docker-image

- Docker image を作ります。
- Deemed to agree to the EULA.
- 特定の Chromium バージョン向けの開発環境を作成するため、Docker image 作成時に Chromium Repository をフェッチします。非常に時間がかかります。

#### cr-fetch-src

- Chromium ソースコードをカレントディレクトリにフェッチします。

#### cr-exec-env

- `cr-setup-docker-image` で作成したイメージのコンテナを作成し、カレントディレクトリを `/mnt/work` にマウントします。
- カレントディレクトリは Chromium ソースコードの `src` ディレクトリの親ディレクトリでなければなりません。

## Hands on

`120.0.6099.234` 向けの Docker image を作成する。

```sh
cr-setup-docker-image --apt-country jp
```

Chromium ソースコードをホストにフェッチする

```sh
mkdir -p ~/work/chromium
cd ~/work/chromium
cr-fetch-src
```

作成した Docker image から Docker container に入り、 Chromium をビルドする。

```sh
cd ~/work/chromium
cr-setup-docker-image

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
