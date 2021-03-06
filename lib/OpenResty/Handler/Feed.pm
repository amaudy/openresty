package OpenResty::Handler::Feed;

use strict;
use warnings;

#use Smart::Comments;
use OpenResty::Util;
use Params::Util qw( _HASH _STRING );
use OpenResty::Limits;

use DateTime::Format::Pg;
use DateTime::Format::Strptime;
use OpenResty::FeedWriter::RSS;
use POSIX qw( strftime );
use Data::Structure::Util qw( _utf8_off );
use OpenResty::QuasiQuote::SQL;

use base 'OpenResty::Handler::Base';

__PACKAGE__->register('feed');

sub level2name {
    qw< feed_list feed feed_param feed_exec >[$_[-1]];
}

my $FormatterPattern = '%a, %d %b %Y %H:%M:%S GMT';
my $Formatter = DateTime::Format::Strptime->new(pattern => $FormatterPattern);

sub POST_feed {
    my ($self, $openresty, $bits) = @_;
    my $data = _HASH($openresty->{_req_data}) or
        die "The feed schema must be a HASH.\n";
    my $feed = $bits->[1];

    my $name;
    if ($feed eq '~') {
        $feed = $data->{name};
    }

    if ($name = delete $data->{name} and $name ne $feed) {
        $openresty->warning("name \"$name\" in POST content ignored.");
    }

    $data->{name} = $feed;
    return $self->new_feed($openresty, $data);
}

sub get_feeds {
    my ($self, $openresty, $params) = @_;
    my $sql = [:sql|
        select name, description
        from _feeds
        order by id |];
    return $openresty->select($sql, { use_hash => 1 });
}

sub GET_feed_list {
    my ($self, $openresty, $bits) = @_;
    my $feeds = $self->get_feeds($openresty);
    $feeds ||= [];

    map { $_->{src} = "/=/feed/$_->{name}" } @$feeds;
    $feeds;
}

sub GET_feed {
    my ($self, $openresty, $bits) = @_;
    my $feed = $bits->[1];

    if ($feed eq '~') {
        return $self->get_feeds($openresty);
    }
    if (!$openresty->has_feed($feed)) {
        die "Feed \"$feed\" not found.\n";
    }
    my $sql = [:sql|
        select name, description, view, title, link, logo, copyright, language, author
        from _feeds
        where name = $feed |];

    return $openresty->select($sql, {use_hash => 1})->[0];
}

sub PUT_feed {
    my ($self, $openresty, $bits) = @_;
    my $feed = $bits->[1];
    my $data = _HASH($openresty->{_req_data}) or
        die "column spec must be a non-empty HASH.\n";
    ### $feed
    ### $data
    die "Feed \"$feed\" not found.\n" unless $openresty->has_feed($feed);

    my $update = OpenResty::SQL::Update->new('_feeds');
    $update->where(name => Q($feed));

    my $new_name = delete $data->{name};
    if (defined $new_name) {
        _IDENT($new_name) or
            die "Bad feed name: ", $OpenResty::Dumper->($new_name), "\n";
        $update->set( name => Q($new_name) );
    }

    my $new_desc = delete $data->{description};
    if (defined $new_desc) {
        _STRING($new_desc) or
            die "Bad feed description: ", $OpenResty::Dumper->($new_desc), "\n";
        $update->set( description => Q($new_desc) );
    }

    my $new_lang = delete $data->{language};
    if (defined $new_lang) {
        _STRING($new_lang) or
            die "Bad feed language: ", $OpenResty::Dumper->($new_lang), "\n";
        $update->set( language => Q($new_lang) );
    }

    my $new_view = delete $data->{view};
    if (defined $new_view) {
        _IDENT($new_view) or
            die "Bad feed view: ", $OpenResty::Dumper->($new_view), "\n";
        $update->set(view => Q($new_view));
    }

    my $new_title = delete $data->{title};
    if (defined $new_title) {
        _STRING($new_title) or
            die "Bad feed title: ", $OpenResty::Dumper->($new_title), "\n";
        $update->set(title => Q($new_title));
    }

    my $new_link = delete $data->{link};
    if (defined $new_link) {
        _STRING($new_link) or die "Bad feed link: ", $OpenResty::Dumper->($new_link), "\n";
        $update->set(link => Q($new_link));
    }

    my $new_logo = delete $data->{logo};
    if (defined $new_logo) {
        _STRING($new_logo) or die "Bad feed logo: ", $OpenResty::Dumper->($new_logo), "\n";
        $update->set(logo => Q($new_logo));
    }


    my $new_author = delete $data->{author};
    if (defined $new_author) {
        _STRING($new_author) or die "Bad feed author: ", $OpenResty::Dumper->($new_author), "\n";
        $update->set(author => Q($new_author));
    }

    my $new_copyright = delete $data->{copyright};
    if (defined $new_copyright) {
        _STRING($new_copyright) or die "Bad feed copyright: ", $OpenResty::Dumper->($new_copyright), "\n";
        $update->set(copyright => Q($new_copyright));
    }

    ### Update SQL: "$update"
    if (%$data) {
        die "Unknown keys in POST data: ", join(' ', keys %$data), "\n";
    }

    my $retval = $openresty->do("$update") + 0;
    return { success => $retval >= 0 ? 1 : 0 };
}

sub exec_feed {
    my ($self, $openresty, $feed_name, $bits, $cgi) = @_;
    my $select = OpenResty::RestyScript::View->new;
    my $sql = "select title, author, link, view, language, copyright, logo from _feeds where name = " . Q($feed_name);
    ### laser exec_feed: "$sql"
    my $info = $openresty->select($sql, { use_hash => 1 })->[0];
    my $view = $info->{view} or die "View name not found.\n";
    my $data = OpenResty::Handler::View->exec_view($openresty, $view, $bits, $cgi);
    my $now = strftime $FormatterPattern, gmtime;

    my $rss = OpenResty::FeedWriter::RSS->new(
      {
        title          => $info->{title},
        link           => $info->{link},
        language       => $info->{language},
        description    => $info->{description},
        copyright      => $info->{copyright},
        pubDate        => $now,
        lastBuildDate  => $now,
        generator      => 'OpenResty RSS Feed Writer',
        image => $info->{logo} ? {
            url   => $info->{logo},
            link  => $info->{link},
            title => $info->{title}
        } : undef,
      }
    );
    ### Begin...

    for my $item (@{ $data }) {
        if (!exists $item->{title}) {
            die "Column \"title\" not found in view \"$view\".\n";
        }
        my $title = $item->{title};

        if (!exists $item->{link}) {
            die "Column \"link\" not found in view \"$view\".\n";
        }
        my $link = $item->{link} || $info->{link}; 

        if (!exists $item->{content}) {
            die "Column \"content\" not found in view \"$view\".\n";
        }
        my $content = $item->{content};

        if (!exists $item->{published}) {
            die "Column \"published\" not found in view \"$view\".\n";
        }
        my $published = $item->{published};

        my $author = $item->{author} || $info->{author};

        my $entry = {
            title => $title,
            link => $link,
            description => $content,
            pubDate => time_pg2rss($published),
            category => $item->{category},
            comments => $item->{comments},
            author => $author,
        };
        $rss->add_entry($entry);
    }
    ### DONE...
    #local *_ = \($rss->as_xml);
    #_utf8_off($_);
    $openresty->{_bin_data} = $rss->as_xml;
    _utf8_off($openresty->{_bin_data});
    $openresty->{_type} = 'application/rss+xml; charset=utf-8';
    return undef;
}

sub GET_feed_exec {
    my ($self, $openresty, $bits) = @_;
    my $feed = $bits->[1];

    die "Feed \"$feed\" not found.\n" unless $openresty->has_feed($feed);
    return $self->exec_feed($openresty, $feed, $bits, $openresty->{_cgi});
}

sub feed_count {
    my ($self, $openresty) = @_;
    return $openresty->select("select count(*) from _feeds")->[0][0];
}

sub new_feed {
    my ($self, $openresty, $data) = @_;
    if (!$openresty->is_unlimited) {
        my $nfeeds = $self->feed_count($openresty);
        if ($nfeeds >= $FEED_LIMIT) {
            die "Exceeded feed count limit $FEED_LIMIT.\n";
        }
    }

    my $res;
    my $name = delete $data->{name} or
        die "No 'name' specified.\n";
    _IDENT($name) or die "Bad feed name: ", $OpenResty::Dumper->($name), "\n";
    if ($openresty->has_feed($name)) {
        die "Feed \"$name\" already exists.\n";
    }

    my $title = delete $data->{title};
    if (!defined $title) {
        die "No 'title' specified.\n";
    }
    _STRING($title) or die "Bad title: ", $OpenResty::Dumper->($title), "\n";

    my $view = delete $data->{view};
    if (!defined $view) {
        die "No 'view' specified.\n";
    }
    _STRING($view) or die "Bad view: ", $OpenResty::Dumper->($view), "\n";
    if ( ! $openresty->has_view($view) ) {
        die "View \"$view\" not found.\n";
    }

    my $author = delete $data->{author};
    if (defined $author) {
        _STRING($author) or die "Bad author: ", $OpenResty::Dumper->($author), "\n";
    }

    my $logo = delete $data->{logo};
    if (defined $logo) {
        _STRING($logo) or die "Bad logo: ", $OpenResty::Dumper->($logo), "\n";
    }

    my $link = delete $data->{link};
    if (!defined $link) {
        die "No 'link' specified.\n";
    }
    _STRING($link) or die "Bad author: ", $OpenResty::Dumper->($link), "\n";

    my $desc = delete $data->{description};
    if (defined $desc) {
        _STRING($desc) or die "Feed description must be a string.\n";
    }

    my $copyright = delete $data->{copyright};
    if (defined $copyright) {
        _STRING($copyright) or die "Feed copyright must be a string.\n";
    }

    my $language = delete $data->{language};
    if (defined $language) {
        _STRING($language) or die "Feed language must be a string.\n";
    }

    if (%$data) {
        die "Unknown keys: ", join(" ", keys %$data), "\n";
    }

    my $sql = [:sql|
        insert into _feeds (name, view, title, link, description, copyright, language, author, logo)
        values($name, $view, $title, $link, $desc, $copyright, $language, $author, $logo) |];

    return { success => $openresty->do($sql) ? 1 : 0 };

}

sub DELETE_feed {
    my ($self, $openresty, $bits) = @_;
    my $feed = $bits->[1];
    _IDENT($feed) or $feed eq '~' or
        die "Bad feed name: ", $OpenResty::Dumper->($feed), "\n";
    if ($feed eq '~') {
        return $self->DELETE_feed_list($openresty);
    }
    if (!$openresty->has_feed($feed)) {
        die "Feed \"$feed\" not found.\n";
    }
    my $sql = "delete from _feeds where name = " . Q($feed);
    return { success => $openresty->do($sql) >= 0 ? 1 : 0 };
}

sub DELETE_feed_list {
    my ($self, $openresty, $bits) = @_;
    my $sql = "truncate _feeds;";
    return { success => $openresty->do($sql) >= 0 ? 1 : 0 };
}

sub time_pg2rss {
    my $time = shift;
    return undef if !$time;
    my $dt;
    eval {
        $dt = DateTime::Format::Pg->parse_timestamp_with_time_zone($time);
    };
    if (!$dt) { return $time }
    #print DateTime::Format::Pg->format_time_with_time_zone($dt);
    # Fri, 04 Apr 2008 08:36:27 GMT
    $dt->set_time_zone('GMT');
    $dt->set_formatter($Formatter);
    return "$dt";
}

1;
__END__

=head1 NAME

OpenResty::Handler::Feed - The feed handler for OpenResty

=head1 SYNOPSIS

=head1 DESCRIPTION

This OpenResty handler class implements the Feed API.

Currently only RSS 2.0 is supported.

=head1 METHODS

=head1 AUTHOR

Agent Zhang (agentzh) C<< <agentzh@yahoo.cn> >>

=head1 SEE ALSO

L<OpenResty::Handler::View>, L<OpenResty::Handler::Role>, L<OpenResty::Handler::Action>, L<OpenResty::Handler::Model>, L<OpenResty::Handler::Version>, L<OpenResty::Handler::Captcha>, L<OpenResty::Handler::Login>, L<OpenResty>.

