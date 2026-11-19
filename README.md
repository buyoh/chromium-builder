# chromium-builder

Create a docker image for the Chromium development environment.

## Install

Add `bin` directory into PATH in the profile such as `.bashrc`.

```sh
export PATH="/path/to/chromium-builder/bin:$PATH"
```

## Hands on

### basic

Create a base Docker image for the Chromium development environment.

```sh
cr-setup-base-docker-image --apt-country jp --no-cache
```

Fetch the Chromium source code.

```sh
cr-fetch-src --cr 132 --dest ~/work/chromium
```

Create a build Docker image from the repository. Refer to `chrome/VERSION` for the Docker image name.

```sh
cr-setup-builder-docker-image --cr-dir ~/work/chromium
```

Enter the Docker container from the created build Docker image and build Chromium.

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

Start Chromium.

```sh
cd ~/work/chromium/src/out/release
./content_shell https://example.com
```

Set up the development environment with vscode. (clangd extensions are required)

```sh
cd ~/work/chromium/src/
cp -r tools/vscode .vscode
tools/clang/scripts/generate_compdb.py -p out/release > compile_commands.json
```

## scripts

For more details, refer to the `--help` option of each script.

- `cr-setup-base-docker-image` : Create a base Docker image that is common for all Chromium versions.
- `cr-fetch-src` : Fetch the Chromium source code.
- `cr-setup-builder-docker-image` : Create a build Docker image from the Chromium source code.
- `cr-exec-env` : Enter the Docker container from the created build Docker image.

## Tests

```sh
for test in tests/test-*.sh; do bash "$test"; done
```
