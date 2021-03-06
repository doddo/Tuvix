#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;

BEGIN {unshift @INC, "$FindBin::Bin/../lib"}

use Mojo::Unicode::UTF8;
use Mojolicious::Lite;

use Plerd::Util;

use Try::Tiny;
use Tuvix;
use Tuvix::ExtendedPlerd;
use Tuvix::PlerdHelper;

use feature qw/say/;

use Getopt::Long qw/GetOptions/;
use File::Basename qw/basename/;
use Pod::Usage qw/pod2usage/;

my $drop_tables = 0;
my $help = 0;
my $send_webmentions = 0;
my $deploy_schema = 0;
my $config_file = "$FindBin::Bin/../tuvix.conf";

GetOptions("drop-tables" => \$drop_tables,
    "deploy-schema"      => \$deploy_schema,
    "help"               => \$help,
    "send-webmentions"   => \$send_webmentions,
    "config-file=s"      => \$config_file)
    or pod2usage(-exitval => 2, -verbose => 1);

pod2usage(-exitval => 0, -verbose => 1) if $help;

die (sprintf "Unable to locate config file '%s'", $config_file)
    unless (-e $config_file);

plugin 'Config' => { file => $config_file };
plugin 'DefaultHelpers';

my $config_ref = app->config();

my $plerd = Tuvix::ExtendedPlerd->new($config_ref);

my $ph = Tuvix::PlerdHelper->new(
    db      => \@{app->config('db')},
    db_opts => app->config('db_opts'),
    plerd   => $plerd
);

$ph->deploy_schema($drop_tables) if $deploy_schema;

my $posts = $ph->publish_all;

while (my $post = $posts->next) {
    printf "%-50.48s %s\n", $post->title(), $post->path();
}

if ($send_webmentions){
   $_->send_webmentions() for @{$plerd->posts()};
}

1;

__END__
=encoding utf-8

=head1 NAME

plerdall_db.pl - Publish all posts from source_dir to the db.

=head1 SYNOPSIS

plerdall_db.pl  [option ...]

 Options:
   --config-file       Path to the tuvix.conf file
   --deploy-schema     Wether to deploy the db schema or not.
   --drop-tables       Drop tables when deploying the schema
   --send-webmentions  Send webmentions from posts if applicable
   --help              brief help message

=head1 OPTIONS

=over 4

=item B<--help>

Print a brief help message and exits.

=item B<--config-file>

Path to the tuvix.conf config file.

=item B<--deploy-schema>

Wether to deploy the db schema or not. This is required to when running for the first time

=item B<--drop-tables>

Wether to drop the db tables before deploying the schema or not. Only usable when deploying-schema

=item B<--send-webmentions>

If a published post contains webmentions, this param specifies whether they should be attempted to be sent or not

=back

=cut
