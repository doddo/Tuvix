package Tuvix::Model::Webmentions;
use strict;
use warnings FATAL => 'all';

use Moose;
use Mojo::URL;
use Carp;

use Web::Mention::Mojo;

has 'base_uri' => (
    isa      => 'Mojo::URL',
    is       => 'ro',
    required => 1,
);

has 'log' => (
    is      => 'ro',
    isa     => 'Mojo::Log',
    default => sub {Mojo::Log->new}
);


sub get_webmentions_from_post {
    my $self = shift;
    my $post = shift;
    unless ($post->isa('Tuvix::Schema::Result::Post')) {
        cluck(sprintf("Input argument was not a 'Tuvix::Schema::Result::Post' as expected but a %s\n",
            ref $post));
        return;
    }

    my $source_uri = Mojo::URL
        ->new($self->base_uri)
        ->path($post->uri->path)
        ->to_abs
        ->to_string;

    return Web::Mention::Mojo->new_from_html(
        source => $source_uri,
        html   => $post->body,
    );

}

sub send_webmentions {
    my $self = shift;

    my %report = (
        attempts  => 0,
        delivered => 0,
        sent      => 0,
    );
    foreach (@_) {
        $report{attempts}++;

        if ($_->send) {
            $self->log->info(sprintf "Sent webmention to endpoint [%s] from [%s].",
                $_->target, $_->source);
            $report{delivered}++;
        }
        elsif ($_->endpoint) {
            $self->log->info(sprintf "Sent webmention (but delivery was not confirmed) to endpoint [%s] from [%s].",
                $_->target, $_->source());
            $report{sent}++;
        }
    }

    return(\%report);
}

1;