# Contributing to Poolex

Poolex is written in [Elixir](https://elixir-lang.org/).

For branching management, this project uses [git-flow](https://github.com/petervanderdoes/gitflow-avh). The `main` branch is reserved for releases: the development process occurs on `develop` and `feature` branches. Please never commit to main.

You can use [asdf](https://asdf-vm.com/) to set up required Elixir and OTP. Current versions are listed in the file `.tool-versions`.

## Setup

### Local repository

1. Fork the repository.
2. Clone your fork to a local repository:

    ```shell
    git clone https://github.com/your-login/poolex.git
    cd poolex
    ```

3. Checkout `develop`:

    ```shell
    git checkout develop
    ```

### Development environment (using asdf)

1. Install asdf by [Getting Started guideline](https://asdf-vm.com/guide/getting-started.html)
2. Add plugins for elixir and OTP

    ```shell
    asdf plugin-add elixir https://github.com/asdf-vm/asdf-elixir.git
    asdf plugin add erlang https://github.com/asdf-vm/asdf-erlang.git
    ```

3. Install tools:

    ```shell
    cd poolex
    asdf install
    ```

### Development environment (without asdf)

Please see [installation instructions](https://elixir-lang.org/install.html).

### Git-flow

If you want to use `git-flow` CLI, please check [installation instructions](https://github.com/petervanderdoes/gitflow-avh/wiki/Installation).

### Building the project

1. Fetch the project dependecies:

    ```shell
    cd poolex
    mix deps.get
    ```

2. Run the static analyzers:

    ```shell
    mix check
    ```

## Workflow

To make a change, please use this workflow:

1. Checkout `develop` and apply the last upstream changes (use rebase, not merge!):

    ```shell
    git checkout develop
    git fetch --all --prune
    git rebase upstream/develop
    ```

2. For a tiny patch, create a new branch with an explicit name:

    ```shell
    git checkout -b <my_branch>
    ```

    Alternatively, if you are working on a feature which would need more work, you can create a feature branch with `git-flow`:

    ```shell
    git flow feature start <my_feature>
    ```

    *Note: always open an issue and ask before starting a big feature, to avoid it not beeing merged and your time lost.*

3. When your feature is ready, feel free to use [interactive rebase](https://help.github.com/articles/about-git-rebase/) so your history looks clean and is easy to follow. Then, apply the last upstream changes on `develop` to prepare integration:

    ```shell
    git checkout develop
    git fetch --all --prune
    git rebase upstream/develop
    ```

4. If there were commits on `develop` since the beginning of your feature branch, integrate them by **rebasing** if your branch has few commits, or merging if you had a long-lived branch:

    ```shell
    git checkout <my_feature_branch>
    git rebase develop
    ```

    *Note: the only case you should merge is when you are working on a big feature. If it is the case, we should have discussed this before as stated above.*

5. Run the tests and static analyzers to ensure there is no regression and all works as expected:

    ```shell
    mix check
    ```

6. If it’s all good, open a pull request to merge your branch into the `develop` branch on the main repository.

## Coding style

Please format your code with `mix format` or your editor and follow
[this style guide](https://github.com/christopheradams/elixir_style_guide).

All contributed code must be documented and functions must have typespecs. In general, take your inspiration from the existing code.
