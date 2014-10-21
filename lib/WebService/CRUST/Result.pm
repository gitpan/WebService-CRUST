package WebService::CRUST::Result;
use base qw(Class::Accessor);

use strict;

our $VERSION = '0.4';


__PACKAGE__->mk_accessors(qw(
    result
    crust
));


sub new {
    my ($class, $h, $crust) = @_;
    
    my $self = bless {}, $class;
    $self->result($h);
    $self->crust($crust);

    return $self;
}



sub string {
    my $self = shift;
    
    return scalar $self->result;
}

# Stringify
use overload
	'""'     => sub { shift->string },
	fallback => 1;



sub AUTOLOAD {
    my $self = shift;
    our $AUTOLOAD;

    # Don't override DESTROY
    return if $AUTOLOAD =~ /::DESTROY$/;

    ( my $method = $AUTOLOAD ) =~ s/.*:://s;

    return unless $self->result and defined $self->result->{$method};
        
    my $result = $self->result->{$method};
    
    $self->{_cache}->{$method} and return $self->{_cache}->{$method};

    if (ref $result eq 'HASH') {
        # Inflate pointers to other CRUST objects
        if (exists $result->{'CRUST__Result'}) {

            my $crust = $self->crust
                ? $self->crust
                : new WebService::CRUST;

            my $href   = new URI($result->{href});
            my $action = $result->{CRUST__Result};
            
            my %args = %{$result->{args}};

            my $full_href = $crust->response
                ? $href->abs($crust->response->base)
                : $href;

            my $r = $crust->request(
                $action,
                $full_href,
                %args
            );

            $self->{_cache}->{$method} = $r;
        }
        else {
            $self->{_cache}->{$method} = WebService::CRUST::Result->new(
                $result, $self->crust
            );
        }
    }
    elsif (ref $result eq 'ARRAY') {
        my @results = @$result;

        if ($results[1]) {
            my @response;
            foreach my $r (@results) {
                push @response, WebService::CRUST::Result->new($r, $self->crust);
            }
            return wantarray ? @response : \@response;
        }
        else {
            return WebService::CRUST::Result->new(shift @results, $self->crust);
        }
    }
    else {
        $self->{_cache}->{$method} = $result;
    }

    return $self->{_cache}->{$method};
}


1;

__END__


=head1 NAME

WebService::CRUST::Result

=head1 SYNOPSIS

  my $r = new Webservice::CRUST::Result->new($val, [$crust]);

Note that this object is generally only helpful when it is created by a
L<WebService::CRUST> call.

=head1 METHODS

=item string

The method used to stringify the object

=item result

An accessor for the raw converted hash result from the request

=item crust

An accessor that points to the WebService::CRUST object that made this request

=head1 AUTOLOAD

Any other method you call tries to get that value from the result.

If the value is a hash ref, it will be returned as another Result object;

If the value is an array ref, it will be returned as an array of Result
objects, or as a ref to the array depending on the context in which it was
called.

If the value is an array ref with only one element, that element is returned.

If the value is scalar it will just be returned as is.

=head1 INFLATION

If the value passed to new is a hash reference with a key called
"CRUST__Result" then this module will look for keys called "args" and "href"
and use them to construct a new request when that value is queried.  For
instance, assume this piece of XML is consumed by a WebService::CRUST object:

    <book name="So Long and Thank For All The Fish">
        <author CRUST__Result="GET">
            <args first="Douglas" last="Adams" />
            <href>http://someservice/author</href>
        </author>
        <price>42.00</price>
    </book>


    $crust->name;   # Returns 'So Long and Thanks For All The Fish'
    $crust->price;  # Returns '42.00'
    $crust->author; # Returns the results of a CRUST GET request to
                    # http://someservice/author?first=Douglas&last=Adams

This is pretty useful when you are exposing a database and you want to be able
to follow relations fairly easily.

=head1 SEE ALSO

L<WebService::CRUST>

=cut