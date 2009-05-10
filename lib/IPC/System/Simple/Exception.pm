package IPC::System::Simple::Exception;

use strict;
use warnings;
use Carp;
use Config;
use overload '""' => "stringify", "0+" => "stringify";

use constant ISSE_UNKNOWN   => 0;
use constant ISSE_SUCCESS   => 1;
use constant ISSE_FSTART    => 2;
use constant ISSE_FSIGNAL   => 3;
use constant ISSE_FINTERNAL => 4;
use constant ISSE_FBADEXIT  => 5;
use constant ISSE_FPLUMBING => 6;

my @Signal_from_number = split(' ', $Config{sig_name});

our %DEFAULTS = (
    type              => ISSE_UNKNOWN,
    exit_value        => -1,
    signal_number     => -1,
    started_ok        => 1,
    command           => "unknown",
    function          => "unknown",
    args              => [],
    format            => 'unknown error',
    fmt_args          => [],
    allowable_returns => [0],
);

my $USEDBY = "IPC::System::Simple";
sub import { $USEDBY = caller; return }

sub new {
    my $class = shift;
    my $this = bless {%DEFAULTS}, $class;

    my ($package, $file, $line, $sub);

    my $depth = 0;
    while (1) {
        $depth++;
        ($package, $file, $line, $sub) = CORE::caller($depth);

        # Skip up the call stack until we find something outside
        # of the caller, $class or eval space

        next if $package->isa($USEDBY);
        next if $package->isa($class);
        next if $package->isa(__PACKAGE__);
        next if $file =~ /^\(eval\s\d+\)$/;

        last;
    }

    # We now have everything correct, *except* for our subroutine
    # name.  If it's __ANON__ or (eval), then we need to keep on
    # digging deeper into our stack to find the real name.  However we
    # don't update our other information, since that will be correct
    # for our current exception.

    my $first_guess_subroutine = $sub;
    while (defined $sub and $sub =~ /^\(eval\)$|::__ANON__$/) {
        $depth++;
        $sub = (CORE::caller($depth))[3];
    }

    # If we end up falling out the bottom of our stack, then our
    # __ANON__ guess is the best we can get.  This includes situations
    # where we were called from the top level of a program.

    if (not defined $sub) {
        $sub = $first_guess_subroutine;
    }

    $this->{package}  = $package;
    $this->{file}     = $file;
    $this->{line}     = $line;
    $this->{caller}   = $sub;

    return $this->set(@_);
}

sub fail_start {
    my $class = shift;
    my $this  = $class->new(@_,
        started_ok => undef,
        type       => ISSE_FSTART,
        format     => '"*C" failed to start: "%s"', # *C is the command
        fmt_args   => [qw(errstr)],
    );

    return $this;
}

sub fail_signal {
    my $class = shift;
    my $this  = $class->new(@_,
        type     => ISSE_FSIGNAL,
        format   => '"*C" died to signal "%s" (%d)%s', # *C is the command
        fmt_args => [qw/signal_name() signal_number _corestr()/],
    );

    return $this;
}

sub fail_internal {
    my $class = shift;
    my $this  = $class->new(@_,
        type     => ISSE_FINTERNAL,
        format   => 'Internal error in *U: %s', # *U is the USEDBY pacakge name
        fmt_args => [qw/errstr/],
    );

    return $this;
}

sub fail_badexit {
    my $class = shift;
    my $this  = $class->new(@_,
        type     => ISSE_FBADEXIT,
        format   => '"*C" unexpectedly returned exit value %d', # *C is the command
        fmt_args => [qw(exit_value)],
    );

    return $this;
}

sub fail_plumbing {
    my $class = shift;
    my $this  = $class->new(@_,
        type     => ISSE_FPLUMBING,
        format   => 'Error in IPC::System::Simple plumbing: "%s" - "%s"',
        fmt_args => [qw(internal_errstr errorstr)],
    );

    return $this;
}

sub success {
    my $class = shift;
    my $this  = $class->new(@_, type=>ISSE_SUCCESS);

    return $this;
}

sub set {
    my ($this, %opts) = @_;

    if( my $ar = delete $opts{caa} ) {
        @opts{qw(command args allowable_returns)} = @$ar;
    }

    @$this{keys %opts} = values %opts;
    return $this
}

sub throw {
    my $this = shift;

    croak $this;
}

sub stringify {
    my $this = shift;

    return $this->exit_value if $this->is_success;

    my $error = sprintf($this->{format}, map {
            my $res;

            if( m/^(.+?)\(\)$/ ) { $res = eval {$this->$1()} || "!?!?!"  }
            else                 { $res = $this->{$_}        || "!?!?!"  }

            $res;

    } @{$this->{fmt_args}});

    my @c = ($this->{command}, @{$this->{args}});
    $error =~ s/\*C/@c/g;
    $error =~ s/\*U/$USEDBY/g;

    return $error . " at $this->{file} line $this->{line}";
}

sub is_success {
    my $this = shift;

    return 1 if $this->{type} == ISSE_SUCCESS;
    return;
}

sub exit_value    { return $_[0]->{exit_value}    }
sub signal_number { return $_[0]->{signal_number} }
sub dumped_core   { return $_[0]->{coredump}      }
sub started_ok    { return $_[0]->{started_ok}    }

sub signal_name {
    my $this = shift;

    return ($Signal_from_number[$this->{signal_number}] || "UNKNOWN");
}

sub child_error       { return $_[0]->{child_error} }
sub command           { return $_[0]->{command} }
sub args              { return (wantarray ? @{$_[0]->{args}} : $_[0]->{args}) }
sub allowable_returns { return (wantarray ? @{$_[0]->{allowable_returns}} : $_[0]->{allowable_returns}) }

sub function { return $_[0]->{function} }
sub file     { return $_[0]->{file}     }
sub package  { return $_[0]->{package}  } ## no critic
sub caller   { return $_[0]->{caller}   } ## no critic

sub type     { return $_[0]->{type} }
sub _corestr { return ($_[0]->{coredump} ? " and dumped core" : "") }

1;
