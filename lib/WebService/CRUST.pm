package WebService::CRUST;
use base 'Class::Data::Inheritable';

use strict;
use LWP;
use HTTP::Cookies;
use HTTP::Request::Common;
use URI;
use URI::QueryParam;



our $VERSION = '0.1';




sub new {
    my ($class, %opt) = @_;


    # Set a default formatter
    $opt{format} or $opt{format} = [ 'XML::Simple', 'XMLin' ];
    
    # Backwards compatibility
    $opt{query} and $opt{params} = $opt{query};
    
    # Only use the library we're using to format with
    eval sprintf "use %s", $opt{format}->[0];
    
    
    return bless { config => \%opt }, $class;    
}


sub get {
    my ($self, $path, %h) = @_;
    return $self->request('GET', $path, %h);
}


sub head {
    my ($self, $path, %h) = @_;
    return $self->request('HEAD', $path, %h);
}


sub put {
    my ($self, $path, %h) = @_;
    return $self->request('PUT', $path, %h);
}


sub post {
    my ($self, $path, %h) = @_;
    return $self->request('POST', $path, %h);
}


sub request {
    my ($self, $method, $path, %h) = @_;

    $method or die "Must provide a method";
    $path or die "Must provide an action";


    # If we have a request key, then use that instead of tacking on a path
    if ($self->{config}->{request_key})
    {
        $self->{config}->{base} or die "request_key requires base option to be set";

        $h{ $self->{config}->{request_key} } = $path;
        $path = undef;
    }

    my $uri = $self->{config}->{base}
        ? URI->new_abs($path, $self->{config}->{base})
        : URI->new($path);

    my $send = $self->{config}->{params}
        ? { %{$self->{config}->{params}}, %h }
        : \%h;

    my $req;
    if ($method eq 'POST') {
        $req = POST $uri->as_string, $send;
    }
    else {
        my $content = delete $send->{-content};
        $self->_add_param($uri, $send);
        $req = HTTP::Request->new($method, $uri);
        $content and $req->add_content( $content );
    }

    $self->{config}->{basic_username} and $self->{config}->{basic_password} and
        $req->authorization_basic(
            $self->{config}->{basic_username},
            $self->{config}->{basic_password}
        );

    my $res = $self->ua->request($req);
    $self->{response} = $res;

    return $self->_format_response($res)
        if $res->is_success;
        
    return undef;
}


sub response { return shift->{response} };


sub _format_response {
    my ($self, $res, $format) = @_;

    $format or $format = $self->{config}->{format};
    my ($class, $method) = @$format;
    
    ref $method eq 'CODE' and return &$method($res->content);
    
    my $o = $class->new(%{$self->{config}->{opts}});
    return $o->$method($res->content);

    # my $result;
    # my $cmd = sprintf '$result = %s($res->content, %{$self->{config}->{opts}});', $format->[1];
    # eval($cmd);
    # return $result;
}


sub ua {
    my ($self, $ua) = shift;

    # If they provided a UA set it
    $ua and $self->{_ua} = $ua;

    # If we already have a UA then return it
    $self->{_ua} and return $self->{_ua};
    
    # Otherwise create our own UA
    $ua = LWP::UserAgent->new;
    $ua->agent("WebService::CRUST/" . $VERSION);    # Set our User-Agent string
    $ua->cookie_jar( {} );              # Support session cookies
    $ua->env_proxy;
    $ua->timeout($self->{config}->{timeout})
        if $self->{config}->{timeout};

    $self->{_ua} = $ua;
    return $ua;
}


sub _add_param {
    my ($self, $uri, $h) = @_;
    
    while (my ($k, $v) = each %$h) { $uri->query_param_append($k => $v) }
}



sub AUTOLOAD {
    my $self = shift;
    our $AUTOLOAD;

    # Don't override DESTROY
    return if $AUTOLOAD =~ /::DESTROY$/;

    # Only get something if we have a base
    $self->{config}->{base} or return;

    (my $method = $AUTOLOAD) =~ s/.*:://s;    
    $method =~ /(get|head|put|post)_(.*)/
        and return $self->$1($2, @_);
        
    return $self->get($method, @_);
}



1;

__END__


=head1 NAME

WebService::CRUST - A lightweight Client for making REST calls

=head1 SYNOPSIS


  use WebService::CRUST;
  use Data::Dumper;
  
  my $c = WebService::CRUST->new;
  
  print Dumper $c->get('http://developer.yahooapis.com/TimeService/V1/getTime',
    appid => 'YahooDemo',
    format => 'ms'
  );

=head1 CONSTRUCTOR

=head2 new

my $c = WebService::CRUST->new( <options> );

=head1 OPTIONS

=head2 base

Sets a base URL to perform actions on.  Example:

  my $c = WebService::CRUST->new(base => 'http://somehost.com/API/');
  $c->get('foo'); # calls http://somehost.com/API/foo

=head2 params

Pass hashref of options to be sent with every query.  Example:

  my $c = WebService::CRUST->new( params => { appid => 'YahooDemo' });
  $c->get('http://developer.yahooapis.com/TimeService/V1/getTime');
  
Or combine with base above to make your life easier:

  my $c = WebService::CRUST->new(
    base => 'http://developer.yahooapis.com/TimeService/V1/',
    params => { appid => 'YahooDemo' }
  );
  $c->get('getTime');
  $c->get('getTime', format => 'ms');

=head2 request_key

Use a specific parm argument for the action, for instance, to talk to Amazon:

  my $c = WebService::CRUST->new(
    base => 'http://webservices.amazon.com/onca/xml?Service=AWSECommerceService',
    request_key => 'Operation',
    params => { AWSAccessKeyId => 'my_key' }
  );

  $c->get('ItemLookup', ItemId => 'B00000JY1X');
  # does a GET on http://webservices.amazon.com/onca/xml?Service=AWSECommerceService&Operation=ItemLookup&ItemId=B00000JY1X&AWSAccessKeyId=my_key

=head2 timeout

Number of seconds to wait for a request to return.  Default is L<LWP>'s
default (180 seconds).

=head2 ua

Pass an L<LWP::UserAgent> object that you want to use instead of the default.

=head2 format

What format to use.  Defaults to XML::Simple.  To use something like L<JSON>:

  my $c = WebService::CRUST->new(format => [ 'JSON', 'objToJson' ]);
  $c->get($url);

The second argument can also be a coderef, so for instance:

  my $c = WebService::CRUST->new(format => [ 'JSON::Syck', sub { JSON::Syck::Load(shift) } ]);
  $c->get($url);

Formatter classes are loaded dynamically if needed, so you don't have to 'use'
them first.

head2 basic_username
head2 basic_password



=head2 opts

A hashref of alternate options to pass the data formatter.

=head1 METHODS

=head2 get

Performs a GET request with the specified options.  Returns undef on failure.

=head2 head

Performs a HEAD request with the specified options.  Returns undef on failure.

=head2 put

Performs a PUT request with the specified options.  Returns undef on failure.

If -content is passed as a parameter, that will be set as the content of the PUT:

  $c->put('something', { -content => $content });

=head2 post

Performs a POST request with the specified options.  Returns undef on failure.

=head2 request

Same as get/post except the first argument is the method to use.

  my $c = WebService::CRUST->new;
  $c->request( 'HEAD', $url );

Returns undef on failure.

=head2 response

The L<HTTP::Response> of the last request.

  $c->get('action');
  $c->response->code eq 200 and print "Success\n";
  
  $c->get('invalid_action') or die $c->response->status_line;

=head2 ua

Get or set the L<LWP::UserAgent> object.

=head1 SEE ALSO

L<Catalyst::Model::WebService::CRUST>, L<LWP>, L<XML::Simple>

=head1 AUTHOR

Chris Heschong E<lt>chris@wiw.orgE<gt>

=cut