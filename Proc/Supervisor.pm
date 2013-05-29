
package Proc::Supervisor;

use strict;
use warnings;
use Carp;

our @ISA = qw(Exporter);
our $VERSION = "0.1";

sub new {
    my ($class, %opt) = @_;
    $class = ref($class) || $class;
    my $self = bless {}, $class;
    
    $self->{ProcNumber} = $self->get_opt('ProcNumber', 1, \%opt);
    $self->{StartTimeout} = $self->get_opt('StartTimeout', 0, \%opt);
    $self->{RestartTimeout} = $self->get_opt('RestartTimeout', 5, \%opt);
    $self->{WorkerFunc} = $self->get_opt('WorkerFunc', undef, \%opt) ||
        croak "Worker function not specified\n";
    $self->{WorkerArgs} = $self->get_opt('WorkerArgs', [], \%opt);
    $self->{OnStart} = $self->get_opt('OnStart', undef, \%opt);
    $self->{OnTerminate} = $self->get_opt('OnTerminate', undef, \%opt);
    $self->{OnError} = $self->get_opt('OnError', undef, \%opt);
    
    $self->{Run} = 0;
    $self->{Workers} = {};
    
    return $self;
}

sub get_opt {
    my ($self, $opt, $default, $opts) = @_;
    return exists $opts->{$opt} ? $opts->{$opt} : $default;
}

sub run {
    my ($self) = @_;
    
    $self->{Run} = 1;
    while( $self->{Run} ) {
        while( keys(%{$self->{Workers}}) < $self->{ProcNumber} ) {
            my $n = $self->{ProcNumber} - keys(%{$self->{Workers}});
            my @pid = $self->start_workers($n);
            
            for( @pid ) {
                $self->{Workers}{$_} = $_;
            }
            
            #if( @pid == $n ) {
                # success
            #}
            #elsif( @pid > 0 ) {
                # partial success
            #}
            #else {
                # fail
            #}
            
            # Restart timeout
            if( @pid < $n ) {
                sleep($self->{RestartTimeout});
            }
        }
        
        my $pid = waitpid(-1, 0);
        if( $pid and exists $self->{Workers}{$pid} ) {
            delete $self->{Workers}{$pid};
            $self->on_terminate_worker($pid);
        }
    }
}

sub stop {
    my ($self) = @_;
    $self->{Run} = 0;
}

sub terminate {
    my ($self, $signal) = @_;
    $signal = 9 unless defined $signal;
    kill $signal, values(%{$self->{Workers}});
}

sub start_workers {
    my ($self, $n) = @_;
    
    return () unless $n > 0;
    
    my @pid;
    for( 1..$n ) {
        my $pid = $self->start_worker();
        if( $pid ) {
            push @pid, $pid;
            $self->on_start_worker($pid);
        }
        else {
            $self->on_error("Cant start worker: $!");
            return @pid;
        }
        
        # Start timeout
        sleep($self->{StartTimeout});
    }
    
    return @pid;
}

sub start_worker {
    my ($self) = @_;
    
    my $pid = fork();
    if( $pid == 0 ) { # That's a child
        $self->{WorkerFunc}->(@{$self->{WorkerArgs}});
        # Exit unless the child exits itself.
        exit(0);
    }
    
    return $pid;
}

sub on_start_worker {
    my ($self, $pid) = @_;
    $self->{OnStart}->($self, $pid) if $self->{OnStart};
}

sub on_terminate_worker {
    my ($self, $pid) = @_;
    $self->{OnTerminate}->($self, $pid) if $self->{OnTerminate};
}

sub on_error {
    my ($self, $strerr) = @_;
    $self->{OnStart}->($self, $strerr) if $self->{OnError};
}

1;



