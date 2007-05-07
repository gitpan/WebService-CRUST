package WebService::CRUST;

use strict;
use LWP;
use HTTP::Cookies;
use HTTP::Request::Common;
use URI;
use URI::QueryParam;

our $VERSION = '0.2';

sub new {
    my ( $class, %opt ) = @_;

    # Set a default formatter
    $opt{format} or $opt{format} = [ 'XML::Simple', 'XMLin' ];

    # Backwards compatibility
    $opt{query} and $opt{params} = $opt{query};

    # Only use the library we're using to format with
    eval sprintf "use %s", $opt{format}->[0];

    return bless { config => \%opt }, $class;
}

sub get {
    my ( $self, $path, %h ) = @_;
    return $self->request( 'GET', $path, %h );
}

sub head {
    my ( $self, $path, %h ) = @_;
    return $self->request( 'HEAD', $path, %h );
}

sub put {
    my ( $self, $path, %h ) = @_;
    return $self->request( 'PUT', $path, %h );
}

sub post {
    my ( $self, $path, %h ) = @_;
    return $self->request( 'POST', $path, %h );
}

sub request {
    my ( $self, $method, $path, %h ) = @_;

    $method or die "Must provide a method";
    $path   or die "Must provide an action";

    # If we have a request key, then use that instead of tacking on a path
    if ( $self->{config}->{request_key} ) {
        $self->{config}->{base}
          or die "request_key requires base option to be set";

        $h{ $self->{config}->{request_key} } = $path;
        $path = undef;
    }

    my $uri =
      $self->{config}->{base}
      ? URI->new_abs( $path, $self->{config}->{base} )
      : URI->new($path);

    my $send =
      $self->{config}->{params}
      ? { %{ $self->{config}->{params} }, %h }
      : \%h;

    my $req;
    if ( $method eq 'POST' ) {
        $self->debug( "POST: %s", $uri->as_string );

        $req = POST $uri->as_string, $send;
    }
    else {
        $self->debug( "%s: %s", $method, $uri->as_string );

        my $content = delete $send->{-content};
        $self->_add_param( $uri, $send );
        $req = HTTP::Request->new( $method, $uri );
        $content and $req->add_content($content);
    }

    if (    $self->{config}->{basic_username}
        and $self->{config}->{basic_password} )
    {
        $self->debug(
            "Sending username/passwd for user %s",
            $self->{config}->{basic_username}
        );

        $req->authorization_basic(
            $self->{config}->{basic_username},
            $self->{config}->{basic_password}
        );
    }

    my $res = $self->ua->request($req);
    $self->{response} = $res;

    $self->debug( "Request Sent: %s", $res->message );

    return $self->_format_response($res)
      if $res->is_success;

    return undef;
}

sub response { return shift->{response} }

sub _format_response {
    my ( $self, $res, $format ) = @_;

    $format or $format = $self->{config}->{format};
    my ( $class, $method ) = @$format;

    ref $method eq 'CODE' and return &$method( $res->content );

    my $o = $class->new( %{ $self->{config}->{opts} } );
    return $o->$method( $res->content );
}

sub ua {
    my ( $self, $ua ) = shift;

    # If they provided a UA set it
    $ua and $self->{_ua} = $ua;

    # If we already have a UA then return it
    $self->{_ua} and return $self->{_ua};

    # Otherwise create our own UA
    $ua = LWP::UserAgent->new;
    $ua->agent( "WebService::CRUST/" . $VERSION ); # Set our User-Agent string
    $ua->cookie_jar( {} );                         # Support session cookies
    $ua->env_proxy;                                # Support proxies
    $ua->timeout( $self->{config}->{timeout} )
      if $self->{config}->{timeout};

    $self->{_ua} = $ua;
    return $ua;
}

sub _add_param {
    my ( $self, $uri, $h ) = @_;

    while ( my ( $k, $v ) = each %$h ) { $uri->query_param_append( $k => $v ) }
}

sub debug {
    my ( $self, $msg, @args ) = @_;

    $self->{config}->{debug}
      and printf STDERR "%s -- %s\n", __PACKAGE__, sprintf( $msg, @args );
}

sub AUTOLOAD {
    my $self = shift;
    our $AUTOLOAD;

    # Don't override DESTROY
    return if $AUTOLOAD =~ /::DESTROY$/;

    # Only get something if we have a base
    $self->{config}->{base} or return;

    ( my $method = $AUTOLOAD ) =~ s/.*:://s;
    $method =~ /(get|head|put|post)_(.*)/
      and return $self->$1( $2, @_ );

    return $self->get( $method, @_ );
}

1;

__END__


=head1 NAME

WebService::CRUST - A lightweight Client for making REST calls

=head1 SYNOPSIS


Simple:

  ## Connect to Yahoo's Time service to see what time it is.

  use WebService::CRUST;
  use Data::Dumper;

  my $url = 'http://developer.yahooapis.com/TimeService/V1/getTime';
  my $w = new WebService::CRUST;

  print Dumper $w->get($url, appid => 'YahooDemo');

Slightly more complex example, where we connect to Amazon and get a list of
albums by the Magnetic Fields:

  ## Connect to Amazon and get a list of all the albums by the Magnetic Fields

  my $w = new WebService::CRUST(
    base => 'http://webservices.amazon.com/onca/xml?Service=AWSECommerceService',
    request_key => 'Operation',
    params => { AWSAccessKeyId => 'my_amazon_key' }
  );

  my $result = $w->ItemSearch(
    SearchIndex => 'Music',
    Keywords => 'Magnetic Fields'
  )->{Items};

  for (@{$result->{Item}}) {
    printf "%s - %s\n", 
      $_->{ASIN}, 
      $_->{ItemAttributes}->{Title};
  }


=head1 CONSTRUCTOR

=head2 new

my $w = new WebService::CRUST( <options> );

=head1 OPTIONS

=head2 base

Sets a base URL to perform actions on.  Example:

  my $w = new WebService::CRUST(base => 'http://somehost.com/API/');
  $w->get('foo'); # calls http://somehost.com/API/foo
  $w->foo;        # Same thing but AUTOLOADED

=head2 params

Pass hashref of options to be sent with every query.  Example:

  my $w = new WebService::CRUST( params => { appid => 'YahooDemo' });
  $w->get('http://developer.yahooapis.com/TimeService/V1/getTime');
  
Or combine with base above to make your life easier:

  my $w = new WebService::CRUST(
    base => 'http://developer.yahooapis.com/TimeService/V1/',
    params => { appid => 'YahooDemo' }
  );
  $w->getTime(format => 'ms');

=head2 request_key

Use a specific param argument for the action veing passed, for instance, when
talking to Amazon, instead of calling /method you have to call ?Operation=method.
Here's some example code:

  my $w = new WebService::CRUST(
    base => 'http://webservices.amazon.com/onca/xml?Service=AWSECommerceService',
    request_key => 'Operation',
    params => { AWSAccessKeyId => 'my_key' }
  );

  $w->ItemLookup(ItemId => 'B00000JY1X');
  # does a GET on http://webservices.amazon.com/onca/xml?Service=AWSECommerceService&Operation=ItemLookup&ItemId=B00000JY1X&AWSAccessKeyId=my_key

=head2 timeout

Number of seconds to wait for a request to return.  Default is L<LWP>'s
default (180 seconds).

=head2 ua

Pass an L<LWP::UserAgent> object that you want to use instead of the default.

=head2 format

What format to use.  Defaults to XML::Simple.  To use something like L<JSON>:

  my $w = new WebService::CRUST(format => [ 'JSON', 'objToJson' ]);
  $w->get($url);

The second argument can also be a coderef, so for instance:

  my $w = new WebService::CRUST(
      format => [ 'JSON::Syck', sub { JSON::Syck::Load(shift) } ]
  );
  $w->get($url);

Formatter classes are loaded dynamically if needed, so you don't have to 'use'
them first.

head2 basic_username

The HTTP_BASIC username to send for authentication

head2 basic_password

The HTTP_BASIC password to send for authentication

  my $w = new WebService::CRUST(
      basic_username => 'user',
      basic_password => 'pass'
  );
  $w->get('http://something/');

=head2 opts

A hashref of alternate options to pass the data formatter.

=head2 debug

Turn debugging on or off.

=head1 METHODS

=head2 get

Performs a GET request with the specified options.  Returns undef on failure.

=head2 head

Performs a HEAD request with the specified options.  Returns undef on failure.

=head2 put

Performs a PUT request with the specified options.  Returns undef on failure.

If -content is passed as a parameter, that will be set as the content of the
PUT request:

  $w->put('something', { -content => $content });

=head2 post

Performs a POST request with the specified options.  Returns undef on failure.

=head2 request

Same as get/post except the first argument is the method to use.

  my $w = new WebService::CRUST;
  $w->request( 'HEAD', $url );

Returns undef on failure.

=head2 response

The L<HTTP::Response> of the last request.

  $w->get('action');
  $w->response->code eq 200 and print "Success\n";
  
  $w->get('invalid_action') or die $w->response->status_line;

=head2 ua

Get or set the L<LWP::UserAgent> object.

=head2 debug

Mostly internal method for debugging.  Prints a message to STDERR by default.

=head1 AUTOLOAD

WebService::CRUST has some AUTOLOAD syntactical sugar, such that the following
are equivalent:

  my $w = new WebService::CRUST(base => 'http://something/');

  # GET request examples
  $w->get('foo', key => $val);
  $w->get_foo(key => $val);
  $w->foo(key => $val);

  # POST request examples
  $w->post('foo', key => $val);
  $w->post_foo(key => $val);

The pattern is $obj->(get|head|post|put)_methodname;


=head1 SEE ALSO

L<Catalyst::Model::WebService::CRUST>, L<LWP>, L<XML::Simple>

=head1 AUTHOR

Chris Heschong E<lt>chris@wiw.orgE<gt>

=cut
