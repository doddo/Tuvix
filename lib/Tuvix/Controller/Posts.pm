package Tuvix::Controller::Posts;
use Mojo::Unicode::UTF8;

use Mojo::Base 'Mojolicious::Controller';
use Mojolicious;
use Mojo::Util qw/url_escape/;

use Tuvix::Model::Posts;

use Mojo::JSON qw(decode_json);
use Mojo::Parameters;
use Try::Tiny;

use DateTime;

use strict;
use warnings FATAL => 'all';

sub get_posts {
    my $c = shift;
    my $page = $c->param('page') || 1;
    my $template = 'post';
    my $posts_per_page = $c->param('posts_per_page') || 10;
    my $format = 'html';

    $c->res->headers->append(
        Link => sprintf('<%s>; rel="webmention"', $c->webmention_url->to_abs));

    if ($c->param('feed') && $c->param('feed') eq 'rss') {
        $posts_per_page = 100;
        $page = 1;
        $template = 'rss';
        $format = 'xml'
    }

    my $posts = defined $c->param('tag')
        ? $c->posts->resultset->get_posts_from_tag($c->param('tag'), $page, $posts_per_page)
        : $c->posts->resultset->get_posts_from_query({ type => 'post' }, $page, $posts_per_page);

    my $pages = $c->posts->resultset->get_posts_from_query({ type => 'page' });

    return $c->reply->not_found unless ($posts->count);

    $c->stash(
        page  => $page,
        title => $c->site_info->title,
        posts => $posts,
        pages => $pages,
        path  => $c->req->url->path
    );
    $c->render(
        template => $template,
        format   => $format
    )
}

sub get_posts_from_path {
    my $c = shift;

    my $posts = $c->posts->get_posts_from_query({ 'path' => $c->url_for });

    $c->res->headers->append(
        Link => sprintf('<%s>; rel="webmention"', $c->webmention_url->to_abs));

    return $c->reply->not_found unless ($posts->count);

    my $pages = $c->posts->get_posts_from_query({ type => 'page' });

    $c->stash(
        page  => 1,
        title => sprintf("%s - %s ", ($posts->all)[0]->title, $c->site_info->title),
        posts => $posts,
        pages => $pages,
    );
    $c->render(
        template => 'post'
    )
}

sub get_archive {
    my $c = shift;
    my $year;
    my $month;
    my $rs = $c->posts->resultset;
    my $latest_post = $rs->get_latest;
    my $dt = $latest_post ? $latest_post->date : DateTime->now;
    my $time_zone = $c->config('time_zone') // DateTime::TimeZone->new(name => 'local');

    unless ($c->param('year') && $c->param('month')) {
        $year = $dt->year;
        $month = $dt->month;
    }
    else {
        $year = $c->param('year');
        $month = $c->param('month');

        unless ($year =~ m/^\d+$/ && ($year >= 1347 && $year <= $dt->year)) {
            $c->render(status => 401, text => "Invalid Year");
            return;
        }
        unless ($month =~ m/^\d+$/ && $month >= 1 && ($month <= $dt->month || ($year < $dt->year && $month <= 12))) {
            $c->render(status => 401, text => "Invalid Month");
            return;
        }
    }

    my $wanted_date_start = DateTime->new(
        year      => $year,
        month     => $month,
        day       => 1,
        hour      => 0,
        minute    => 0,
        second    => 0,
        time_zone => $time_zone,
    );

    my $posts = $rs->get_posts_from_month($wanted_date_start);
    my $pages = $c->posts->get_posts_from_query({ type => 'page' });

    $c->stash(
        wanted => $wanted_date_start,
        title  => 'Archive',
        posts  => $posts,
        pages  => $pages
    );
    $c->render(
        template => 'archive',
    )
}


sub search {
    my $c = shift;

    my $pages = $c->posts->get_posts_from_query({ type => 'page' });
    my $query = $c->param('q');
    my $posts;

    if ($query) {
        my $self = shift;
        chomp($query);
        $posts = $c->posts->resultset->search({
            -or => [
                description => { -like => "%${query}%" },
                title       => { -like => "%${query}%" },
            ]
        },
            {
                order_by => { -desc => qw/date/ },
            });

        $c->res->code(
            $posts->count ? 200 : 404
        );
    }
    else {
        # 400 if the search param is missing
        $c->res->code(400);
    }

    $c->stash(
        title => 'Search',
        posts => $posts,
        pages => $pages,
        query => $query,
    );
    $c->render(
        template => 'search',
    )
}

sub load_next {
    my $c = shift;
    $c->on(message => sub {
        my ($self, $json_message) = @_;

        try {
            my $message = decode_json $json_message;
            my $params =  Mojo::Parameters->new($$message{query} =~ s/^\?//r);
            my $posts = $params->param('tag')
                ? $c->posts->resultset->get_posts_from_tag($params->param('tag'), $$message{page})
                : $self->posts->get_posts_from_query({ type => 'post' }, $$message{page});

            if ($posts->count) {
                while (my $post = $posts->next) {
                    $self->stash(post => $post);
                    $self->send($self->render_to_string(template => '_post'));
                }
            }
            else {
                $self->send('EOF');
            };
        }
        catch {
            $self->app->log->warn("Unable to decode incoming ws JSON (or other error encountered): ". $_);
        }
    });
}

1;
