use strict;
use warnings;

use Path::Class;
my $root = dir(__FILE__)->parent;

use Plack::Builder;
use Path::Class;

use lib 'lib';
use XPathFeed;

use Amon2::Lite;

sub xpathfeed {
    my ($request) = @_;
    my $xpf = XPathFeed->new_from_query($request);

    if (exists $ENV{XPF_CACHE} && $ENV{XPF_CACHE} eq 'Cache::Redis') {
        require Cache::Redis;

        my $args = {
            namespace => 'xpathfeed',
        };

        my $redis_url = $ENV{REDISCLOUD_URL} || $ENV{REDISTOGO_URL};
        if ($redis_url) {
            my $uri = URI->new($redis_url);
            $uri->scheme('ftp'); # host_port と password を呼べるようにする
            $args->{server}   = $uri->host_port;
            $args->{password} = $uri->password if $uri->password;
        }

        $xpf->cache(Cache::Redis->new($args));
    }

    return $xpf;
}

get '/' => sub {
    my ($c) = @_;
    my $xpf = xpathfeed($c->req);
    return $c->render(
        index => {
            xpf => $xpf,
            GA_WEB_PROPERTY_ID => $ENV{GA_WEB_PROPERTY_ID},
            GA_CONFIG => $ENV{GA_CONFIG},
        }
    );
};

get '/frame' => sub {
    my ($c) = @_;
    my $xpf = xpathfeed($c->req);
    return $c->create_response(
        200,
        [
            'Content-Type'    => 'text/html',
            'X-Frame-Options' => 'SAMEORIGIN',
        ],
        [$xpf->frame_content],
    );

};

get '/feed' => sub {
    my ($c) = @_;
    my $xpf = xpathfeed($c->req);
    return $c->create_response(
        200,
        [
            'Content-Type'    => 'text/xml',
        ],
        [$xpf->feed],
    );

};

builder {
    enable 'Plack::Middleware::Static',
        path => qr{^/(?:images|css|js)/},
        root => $root->subdir('static');

    enable 'Plack::Middleware::ReverseProxy';

    my $fh_access;
    if (exists $ENV{XPF_ACCESS_LOG} && $ENV{XPF_ACCESS_LOG} eq 'STDERR') {
        $fh_access = *STDERR;
    } else {
        my $access_log = Path::Class::file($ENV{XPF_ACCESS_LOG} || '/var/log/app/access_log');
        $fh_access = $access_log->open('>>')
            or die "Cannot open >> $access_log: $!";
        $fh_access->autoflush(1);
    }

    enable 'Plack::Middleware::AccessLog::Timed',
        logger => sub {
            print $fh_access @_;
        },
        format => join("\t",
            "time:%t",
            "host:%h",
            "domain:%V",
            "req:%r",
            "status:%>s",
            "size:%b",
            "referer:%{Referer}i",
            "ua:%{User-Agent}i",
            "taken:%D",
        );

    __PACKAGE__->to_app(
        no_x_frame_options => 1,
    );
};

__DATA__
@@ index
<!DOCTYPE html>
<html>
  <head>
    <meta charset="utf-8">
    <title>XPathFeed</title>
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <link href="/css/bootstrap.css" rel="stylesheet">
    <link href="/css/flat-ui.css" rel="stylesheet">
    <link href="/css/xpathfeed.css" rel="stylesheet">
    <link rel="shortcut icon" href="images/favicon.ico">
    <!--[if lt IE 9]>
      <script src="js/html5shiv.js"></script>
    <![endif]-->

    [% IF xpf.feed_uri %]
    <link rel="alternate" type="application/rss+xml" title="RSS" href="[% xpf.feed_uri %]">
    [% END # IF xpf.feed_uri %]

  </head>
  <body>
[% IF GA_WEB_PROPERTY_ID %]
<script>
  (function(i,s,o,g,r,a,m){i['GoogleAnalyticsObject']=r;i[r]=i[r]||function(){
  (i[r].q=i[r].q||[]).push(arguments)},i[r].l=1*new Date();a=s.createElement(o),
  m=s.getElementsByTagName(o)[0];a.async=1;a.src=g;m.parentNode.insertBefore(a,m)
  })(window,document,'script','//www.google-analytics.com/analytics.js','ga');

  ga('create', '[% GA_WEB_PROPERTY_ID %]', '[% GA_CONFIG || "auto" %]');
  ga('send', 'pageview');

</script>
[% END # IF GA_WEB_PROPERTY_ID %]
    <div class="container">
      <div class="headline">
        <h1 class="title-logo"><a href="/">XPathFeed</a></h1>
        <p>Generate RSS Feed from XPath</p>
      </div>
      <div class="row">
        <form action="./" method="get">

          <h2>[% UNLESS xpf.url %]Enter [% END %]URL</h2>
          <input type="text" name="url" value="[% xpf.url %]" placeholder="URL">
          [% IF xpf.url %]

            <h2>Preview <a href="[% xpf.url %]">[% xpf.title %]</a></h2>
            <iframe id="iframe" frameborder="0"></iframe>
            <script>
              setTimeout( function(){
                document.getElementById('iframe').src = '/frame?url=[% xpf.url | uri %]'
              } , 10 );
            </script>

            <h2>[% UNLESS xpf.xpath_list %]Enter [% END %]XPath</h2>

            <input type="text" name="xpath_list" value="[% xpf.xpath_list %]" placeholder="XPath or CSS Selector">

            [% IF xpf.list_size %]

              <h2>List <span style="font-size:80%">([% xpf.list_size %] items)</span></h2>

              <div class="row mbl">
                <div class="span3"><dl><dt>title</dt><dd><input type="text" name="xpath_item_title" value="[% xpf.xpath_item_title%]" placeholder="//a"></dd></div>
                <div class="span3"><dl><dt>link</dt><dd><input type="text" name="xpath_item_link" value="[% xpf.xpath_item_link%]" placeholder="//a/@href"></dd></div>
                <div class="span3"><dl><dt>image</dt><dd><input type="text" name="xpath_item_image" value="[% xpf.xpath_item_image%]" placeholder="//img/@src"></dd></div>
                <div class="span3"><dl><dt>description</dt><dd><input type="text" name="xpath_item_description" value="[% xpf.xpath_item_description%]" placeholder="//*"></dd></div>
                <div class="span12"><input type="submit" value="Customize" class="btn"></div>
              </div>

              [% FOREACH item IN xpf.list %]
                [% LAST IF loop.count > 5 %]
                <div class="row mbl">
                  <div class="span4 palette palette-silver">
                    [% IF item.image %]
                      <img src="[% item.image %]" alt="" style="max-width:80px;max-height:80px;float:right">
                    [% END # IF item.image %]
                    <h4>[% item.title %]</h4>
                    <p>[% item.link %]</p>
                    <p class="palette palette-clouds">[% item.description %]</p>
                    <span style="clear:both"></span>
                  </div>
                  <div class="span8 palette palette-clouds"><pre class="source">[% item.html %]</pre></div>
                </div>[% # div.row %]
              [% END # FOREACH item IN xpf.list %]

              <div class="row">
                <a href="[% xpf.feed_uri %]" class="btn btn-large btn-block palette palette-bright-dark">RSS Feed Here!!</a>
              </div>

            [% ELSE # IF xpf.list_size %]

              <input type="submit" value="Next Step" class="btn">

            [% END # IF xpf.list_size %]

          [% ELSE # IF xpf.url %]

            <input type="submit" value="Next Step" class="btn">

          [% END # IF xpf.url %]
        </form>
      </div>[% # div.row %]
    </div>[% # div.container %]

    <footer>
      <div class="container">
        <div class="row">
          <div class="span12" style="text-align:center">
            <p class="mtl mbl">
              <a href="https://github.com/onishi/xpathfeed">The original version</a> is written by <a href="http://www.hatena.ne.jp/onishi/">id:onishi</a>.
              Modified by <a href="https://github.com/vzvu3k6k/">vzvu3k6k</a>. <a href="https://github.com/vzvu3k6k/xpathfeed">View on GitHub</a>.
            </p>
          </div>
        </div>
      </div>
    </footer>

  </body>
</html>
