package WebService::CRUST::Result;

use strict;

our $VERSION = '0.3';



sub new {
    my ($class, $h, $crust) = @_;
    
    
    my $self = ref $h
        ? bless $h, $class
        : bless { __scalar => $h }, $class;
    
    $self->{__crust} = $crust;
    
    return $self;
}



sub string {
    my $self = shift;
    
    return $self->{__scalar}
        ? $self->{__scalar}
        : scalar $self
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

    return unless defined $self->{$method};
    
    my $result = $self->{$method};
    
    
    $self->{_cache}->{$method} and return $self->{_cache}->{$method};
    
    if (ref $result) {
        # Inflate pointers to other CRUST objects
        if ($result->{'CRUST__Result'}) {
            
            my $crust = $self->{__crust}
                ? $self->{__crust}
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
            
            if ($r->$method) { $r = $r->$method };

            $self->{_cache}->{$method} = WebService::CRUST::Result->new(
                $r, $self->{__crust}
            );
        }
        else {
            $self->{_cache}->{$method} = WebService::CRUST::Result->new(
                $result, $self->{__crust}
            );
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

=head1 INFLATION

If the value passed to new is a hash reference with a key called "CRUST__Result"
then this module will look for keys called "args" and "href" and use them to construct
a new request when that value is queried.  For instance, assume this piece of XML is
consumed by a WebService::CRUST object:

    <book name="So Long and Thank For All The Fish">
        <author CRUST__Result="GET">
            <args first="Douglas" last="Adams" />
            <href>http://someservice/author</href>
        </author>
        <price>$42.00</price>
    </book>


    #crust->name;   # Returns 'So Long and Thanks For All The Fish'
    $crust->price;  # Returns '$42.00'
    $crust->author; # Returns the results of a CRUST GET request to
                    # http://someservice/author?first=Douglas&last=Adams

This is pretty useful when you are exposing a database and you want to be able
to follow relations fairly easily.

=head1 SEE ALSO

L<WebService::CRUST>

=cut