kpatch-bot
==========
Autonomous [kpatch](https://github.com/dynup/kpatch) pull request build and
reporting bot.

Status
------
This project is only a prototype.


Install
-------
* [kpatch](https://github.com/dynup/kpatch) build and testing requirements
* RHEL:	```sudo dnf install curl jq perl-JSON```
* Fedora:	```sudo dnf install curl jq perl-JSON```
* Ubuntu:	```sudo apt-get install curl jq libjson-perl```

Setup
-----
* Create a github [personal API token](https://github.com/blog/1509-personal-api-tokens)
with repo and gist scopes enabled.  This token will be used to periodically
poll for new pull requests as well as posting test results as comments and
test logs as a personal gist.

* Setup ```~/.netrc``` with a line like this:
```
machine api.github.com login <username> password <token_value>
```

Usage
-----

```
monitor_PRs.pl

	-n|name <name>			kpatch-bot posting name
	-d|poll_period <seconds>	PR polling interval
	-p|project <group/project>	GitHub group/project name
	-t|temp_dir <tmpdir path>	Temporary file store
	-v|verbose			Verbose flag
	-y|dry_run			Dry run flag
```
