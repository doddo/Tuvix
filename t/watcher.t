#!/usr/bin/perl
use strict;
use warnings;
use Test::More;

use Mojolicious::Lite;
use Mojo::Unicode::UTF8;

use File::Temp qw/ tempfile :seekable /;
use File::Copy;

use Tuvix::Watcher;
use Tuvix::Schema;

use FindBin;

BEGIN {unshift @INC, ("$FindBin::Bin/lib", "$FindBin::Bin/../lib")}


plan tests => 4;

plugin 'Config' => { file => $FindBin::Bin . '/assets/tuvix.conf' };

my $watcher_pidfile = File::Temp->new(SUFFIX => '.pid');
my $temporary_database = File::Temp->new(SUFFIX => '.db');


my @db_cx = ("dbi:SQLite:${temporary_database}", "", "");
@{${app->config}{'db'}} = @db_cx;

my $dbh = Tuvix::Schema
    ->connect(@db_cx,
        {RaiseError => 1, sqlite_unicode => 1 });

$dbh->deploy({ add_drop_table => 1 });

my $draft_file_s = ${app->config}{'source_path'} . '/../drafts/draft.markdown';
my $draft_file_t = ${app->config}{'source_path'} . '/draft.markdown';

my $pid;

{

    chdir "$FindBin::Bin";

    ${app->config}{'watcher_pidfile'} = $watcher_pidfile->filename;

    my $watcher = Tuvix::Watcher->new(config => app->config);
    $pid = $watcher->start();

    ok($pid, 'forked a new directory watcher process');

    my $watcher2 = Tuvix::Watcher->new(config => app->config);
    my $pid2 = $watcher->start(config => app->config);

    ok(!$pid2, 'second instance does not get a lock');

    my $posts = $dbh->resultset('Post');

    copy($draft_file_s, $draft_file_t) or die $!;

    sleep 3;

    ok ($posts->find({source_file => 'draft.markdown'}),
        "draft is published when file is created in source_path");

    unlink $draft_file_t;

    sleep 3;

    ok (! $posts->find({source_file => 'draft.markdown'}),
        "draft is unpublished when file is removed from source_path");
}

done_testing();

END {
    unlink $draft_file_t;
    unlink $watcher_pidfile;
    unlink $temporary_database;
    kill($pid) if $pid && -f "/proc/$pid";
}


