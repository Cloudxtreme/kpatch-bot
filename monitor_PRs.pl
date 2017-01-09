#!/usr/bin/perl

# Requires:
#   RHEL	sudo dnf install curl jq perl-JSON
#   Fedora	sudo dnf install curl jq perl-JSON
#   Ubuntu	sudo apt-get install curl jq libjson-perl
#
# Create a github personal API token
#   https://github.com/blog/1509-personal-api-tokens
#
# Setup ~/.netrc with a line like this:
#   machine api.github.com login <username> password <token_value>

use Cwd;
use Getopt::Long;
use File::Temp qw(tempfile tempdir);
use JSON;
use strict;
use warnings;

my %opt;

sub verbose($)
{
	my $line = shift;
	print "$line" if $opt{'verbose'};
}

sub process_options()
{
	my $bot_name = `. /etc/os-release && echo "kpatch-bot - \$NAME \$VERSION - \$(uname -r)"`;
	chomp $bot_name;

	# Default values
	$opt{'bot_name'}	= $bot_name;
	$opt{'dry_run'}		= 0;
	$opt{'poll_period'}	= 60*15;
	$opt{'project'} 	= '';
	$opt{'temp_dir'}	= '';
	$opt{'verbose'}		= 0;

	# Command line overrides
	GetOptions (
			"n|name=s"		=> \$opt{'bot_name'},
			"d|poll_period=i"	=> \$opt{'poll_period'},
			"p|project=s"		=> \$opt{'project'},
			"t|temp_dir=s"		=> \$opt{'temp_dir'},
			"v|verbose"		=> \$opt{'verbose'},
			"y|dry_run"		=> \$opt{'dry_run'},
		   );

	# Provide a temporary directory (cleanup on exit) if the
	# user did not provide one on the command line
	if ($opt{'temp_dir'} eq "") {
		$opt{'temp_dir'} = tempdir(CLEANUP => 1);

	# Catch Ctrl-C so Perl will cleanup tempdir
		$SIG{INT} = sub { exit; };
	}
	verbose "tempdir = $opt{'temp_dir'}\n";
	verbose "dry_run = $opt{'dry_run'}\n";
}

sub fetch_pulls($)
{
	my $project = shift;

	# See https://developer.github.com/v3/pulls/
	my $url = "https://api.github.com/repos/$project/pulls";
	my $jq_filter =	" id: .id," .
			" number: .number," .
			" url: .url," .
			" title: .title," .
			" updated_at: .updated_at, " .
			" clone_url: .head.repo.clone_url," .
			" version: .head.ref";

	verbose "fetch_pulls($project)\n";
	verbose "curl $url -> $opt{'temp_dir'}/github_pulls\n";

	# Fetch GitHub pull request info
	`curl --fail --silent $url --output $opt{'temp_dir'}/github_pulls`;

	# Filter out the JSON fields that we're interested in,
	# pipe back through jq to add enclosing [ ]'s to appease
	# decode_json().
	`jq ".[] | { $jq_filter }" $opt{'temp_dir'}/github_pulls | jq --slurp '.' > $opt{'temp_dir'}/github_pulls.json`;

	my $json = `cat $opt{'temp_dir'}/github_pulls.json`;
	verbose "filtered JSON = $json\n";

	my @list = @{ decode_json($json) };
	verbose "curl -> found " . scalar @list . " PRs\n";

	return @list;
}

sub compare_lists($$)
{
	my @old_list = @{$_[0]};
	my @new_list = @{$_[1]};

	my @updated_list;

	verbose "compare_lists()\n";
	if ($opt{'verbose'}) {
		foreach my $new_href (@new_list) {
			my %new_hash = %{$new_href};
			verbose "new_list: $new_hash{'id'} - $new_hash{'updated_at'}\n";
		}
		foreach my $old_href (@old_list) {
			my %old_hash = %{$old_href};
			verbose "old_list: $old_hash{'id'} - $old_hash{'updated_at'}\n";
		}
	}

	# Iterate through all the new pull requests
	foreach my $new_href (@new_list) {

		my %new_hash = %{$new_href};
		my $id_match = 0;
		my $updated = 0;

		# Iterate through all the old pull requests
		foreach my $old_href (@old_list) {

			my %old_hash = %{$old_href};

			# Skip if not an ID match
			next if ($old_hash{'id'} ne $new_hash{'id'}); 

			$id_match = 1;
			verbose "old_list: $old_hash{'id'} = new_list: $new_hash{'id'}\n";

			# Mark as updated if "updated_at" has changed
			if ($old_hash{'updated_at'} ne $new_hash{'updated_at'}) {
				$updated = 1;
				verbose "old_list: $old_hash{'updated_at'} != new_list: $new_hash{'updated_at'}\n";
				last;
			}
		}

		# Consider any pull request that has no prior ID match
		# or has been updated
		push @updated_list, $new_href if (!$id_match or $updated);
	}

	verbose "found " . scalar @updated_list . " updated PRs\n";
	return @updated_list;
}



process_options;

# Set the old and new pull lists such that we don't act on *every*
# PR on program (re)start.
my @pulls_old = fetch_pulls($opt{'project'});
my @pulls_new = @pulls_old;

while(1) {

	my @updated = compare_lists(\@pulls_old, \@pulls_new);

	foreach my $href (@updated) {

		my %pull_hash = %{$href};

		print "testing $pull_hash{'id'} - $pull_hash{'title'}\n";

		my $log_dir = getcwd . "/logs-" . `date --iso-8601=seconds`;
		chomp $log_dir;

		verbose "clone_url: $pull_hash{'clone_url'}\n";
		verbose "version  : $pull_hash{'version'}\n";
		verbose "log_dir  : $log_dir\n";

		# Run the test(s), save the stdout into a 'comment' file
		`echo "$opt{'bot_name'}" > $opt{'temp_dir'}/comment`;
		`tests/do_tests $pull_hash{'clone_url'} $pull_hash{'version'} $log_dir >> $opt{'temp_dir'}/comment`;

		# Concatenate the test logs
		`for l in $log_dir/*; do echo "*** \$l ***"; cat \$l; echo -e '\\n\\n'; done > $opt{'temp_dir'}/logs`;

		# Escape newlines and wrap up the text logs into JSON
		`jq '{content: .}' --raw-input --slurp --compact-output $opt{'temp_dir'}/logs > $opt{'temp_dir'}/logs.json`;

		# Wrap up the log JSON content in a complete gist JSON structure
		# XXX: we're losing '\n' characters in logs.json here!!!
		# `echo "{ \\"description\\": \\"kpatch-bot logs\\", \\"public\\": true, \\"files\\": { \\"PR$pull_hash{'number'}-logs.txt\\": \$(cat $opt{'temp_dir'}/logs.json) } }" > $opt{'temp_dir'}/gist.json`;
		`echo "{ \\"description\\": \\"kpatch-bot logs\\", \\"public\\": true, \\"files\\": { \\"PR$pull_hash{'number'}-logs.txt\\": " >  $opt{'temp_dir'}/gist.json`;
		`cat $opt{'temp_dir'}/logs.json >> $opt{'temp_dir'}/gist.json`;
		`echo " } }" >> $opt{'temp_dir'}/gist.json`;

		# Post the gist
		my $gist_api_url = "https://api.github.com/gists";
		`curl --netrc $gist_api_url --header "Content-Type: application/json" --data \@$opt{'temp_dir'}/gist.json --output $opt{'temp_dir'}/github_gist`;

		# The gist url
		my $gist_url = `jq --raw-output '.html_url' $opt{'temp_dir'}/github_gist`;
		chomp $gist_url;
		print "gist_url = $gist_url\n";

		my $comment = `cat $opt{'temp_dir'}/comment`;
		print "$comment\n";

		# Add gist URL to comment
		`./commentgist $opt{'temp_dir'}/comment $gist_url > $opt{'temp_dir'}/comment_gist`;

		# Convert the text 'comment' into markdown pretty-print
		`./comment2md $opt{'temp_dir'}/comment_gist > $opt{'temp_dir'}/comment.md`;

		# Escape newlines and wrap the markdown comment in JSON
		`awk '{printf "%s\\n", \$0}' $opt{'temp_dir'}/comment.md | jq '{body: .}' --raw-input --slurp --compact-output > $opt{'temp_dir'}/comment.json`;

		unless ($opt{'dry_run'}) {

			# See https://developer.github.com/v3/issues/comments/
			my $url = "https://api.github.com/repos/$opt{'project'}/issues/$pull_hash{'number'}/comments";
			`curl --netrc --include $url --header "Content-Type: application/json" --data \@$opt{'temp_dir'}/comment.json --output $opt{'temp_dir'}/github_comment`;

			my $response = `cat $opt{'temp_dir'}/github_comment`;
			verbose "curl response $response\n";
		}

		sleep 1;
	}

	sleep $opt{'poll_period'};

	@pulls_old = @pulls_new;
	@pulls_new = fetch_pulls($opt{'project'});
}
