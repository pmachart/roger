# Roger
<img src="images/roger.png" height="130" align="right" style="padding-left:30px">

Roger : CLI tool to accelerate the front-end developer's daily tedious tasks.

Don't you just hate having to open two or three different browser tabs after completing every single ticket ? Waiting for slow interfaces that requires you to click everywhere just to update one field ?


## Features

- Opens merge requests
- Runs jenkins jobs
- Updates jira ticket fields

Works great in a multiple project environment thanks to individual config files.


## Usage

Daily usage is fairly simple : just call roger from the terminal !
Most of its options can be automatically infered from what it sees in your working directory (project, branch...)

`Roger` can only be run from inside a git repository, otherwise it will exit.
You can still specify a branch name if you want to run an action on another branch.

Let's break it down :

|Command|Result|
|-|-|
|`roger mr`|Creates a merge request for current branch (don't forget to push it first)|
|`roger mr JIR-123`|Create MR for branch "JIR-123"|
|`roger jenkins`|Runs a jenkins deploy job for your current branch|
|`roger jenkins JIR-123`|Runs a jenkins deploy job for branch "JIR-123"|
|`roger jira`|Updates the jira ticket corresponding to the current branch|
|`roger roger`|Runs all actions in that order : mr, jenkins, jira|

You can supply the arguments in any order.
Contributions for more commands are most welcome.

__Note__ The Jira task updates a custom field with the url of the sandbox url that the jenkins job used. If you need the Jira task to do something else, you'll need to write your own `curl` and refer to Jira's api documentation.

### Additional commands :

|Command|Result|
|-|-|
|`roger help`|Displays basic usage|
|`roger install`|Inserts Roger as an alias in your `.bashrc` (you can change the alias file at the top of the script)|
|`roger install --alias=something`|Inserts Roger in your `.bashrc` with a different alias|
|`roger uninstall`|Finds the alias and removes it|
|`roger autocomplete`|Sets up autocompletion for Roger. Requires admin rights.|



## Configuration

When running `roger` for the first time, you will need to fill in your credentials for the various APIs that `roger` uses.
Roger automatically creates the config file and immediately lets you fill the information with your default editor.
You will need to create authentication tokens, you can't just use your account passwords.
Please read the documentation of the corresponding services on how to generate these tokens.

When running `roger` for the first time in a `git` repository, you will be prompted to configure that project.
Roger will create a config file for this project and will let you edit it.

You can then edit them manually. By default, config files are located in `~/.config/roger`
You can change the variable for this location at the top of the script.


__Note__
If something doesn't work, it might be because the service's API has changed. Check the corresponding documentation.
If that ever happens, I would appreciate it if you could submit an issue about it !


## Installation

### Manual

Installing Roger is fairly simple, all you have to do is save the file and set up an alias to run it.

Just paste the following line wherever you store your aliases (.bashrc .bash_aliases etc.)
```shell
alias roger='path/to/roger.sh'
```
Adjust the path according to where you saved the script.

Then make sure it is executable with `chmod` :
```shell
chmod +x ./roger.sh
```

### Automatic

It can be useful if you want to include this script in your project's or your team's generic tooling.
You can do so by using `roger install` : this will create an alias in your `.bashrc`

By changing the value of the variable at the top of the script, you can change the file containing the alias.
If you want to use it with a different name, try `roger install alias=something`


## Dependencies

### Curl
`curl` is a tool to transfer data to/from a server using various protocols.
It is quite popular and included in most distributions nowadays, but not always, which is why I'm listing it here.

### JQ
`jq` is a cli json processor that makes json parsing in shell much easier and very straightforward.

If you're not already using it, I really recommend you check it out : https://stedolan.github.io/jq/

### Dependency installation
Both of these can be installed by their names with most package managers, including `brew` if you're on macOs.
```shell
apt install curl jq
brew install curl jq
```


## Contributions

As I continue using this script for myself, I will continue adding features to it, and making its configuration easier.

Current features are heavily tied to the workflow of the company I'm currently working in.
We're using Gitlab Enterprise, Jenkins, and Jira Cloud.

If you're not using these things, the `curl` commands can most probably be adapted to your workflow, so fork away, and don't hesitate to share !
