use strict;;
use warnings;

package BarnOwl::Module::AIM;

=head1 NAME

BarnOwl::Module::AIM

=head1 DESCRIPTION

BarnOwl module implementing AIM support via Net::OSCAR

=cut

use BarnOwl;
use BarnOwl::Hooks;

use Net::OSCAR;

no warnings 'redefine';

our @oscars;

sub queue_admin_msg {
    my $err = shift;
    BarnOwl::admin_message('AIM', $err);
}

sub on_connection_changed {
    my ($oscar, $connection, $status) = @_;
    my $fileno = fileno($connection->get_filehandle);
    if ($status eq 'deleted') {
        BarnOwl::remove_io_dispatch($fileno);
    } else {
        my $mode = '';
        $mode .= 'r' if $status =~ /read/;
        $mode .= 'w' if $status =~ /write/;
        BarnOwl::add_io_dispatch($fileno,
                                 $mode,
                                 sub {
                                     my $rin = '';
                                     my $win = '';
                                     vec($rin, $fileno, 1) = 1 if ($status =~ /read/);
                                     vec($win, $fileno, 1) = 1 if ($status =~ /write/);
                                     my $ein = $rin | $win;
                                     select($rin, $win, $ein, 0);
                                     my $read = vec($rin, $fileno, 1);
                                     my $write = vec($win, $fileno, 1);
                                     my $error = vec($ein, $fileno, 1);
                                     $connection->process_one($read, $write, $error);
                                 }
            ) if ($mode);
    }
}

sub on_error {
    my ($oscar, $connection, $errno, $desc, $fatal) = @_;
    queue_admin_msg(sprintf("%sError %i: %s", $fatal ? 'Fatal ' : '', $errno, $desc));
}

sub on_im_in {
    my ($oscar, $sender, $message, $is_away) = @_;
    my $msg = BarnOwl::Message->new(
            type => 'AIM',
            direction => 'in',
            sender => $sender,
            origbody => $message,
            away => $is_away,
            body => zformat($message, $is_away),
            recipient => get_screenname($oscar),
            replycmd =>
                "aimwrite -a '" . get_screenname($oscar) . "' $sender",
            replysendercmd =>
                "aimwrite -a '" . get_screenname($oscar) . "' $sender",
            );
    BarnOwl::queue_message($msg);
}

sub cmd_aimlogin {
    my ($cmd, $user, $pass) = @_;
    if (!defined $user) {
        BarnOwl::error("usage: $cmd screenname [password]");
    } elsif (!defined $pass) {
        BarnOwl::start_password('Password: ',
                                sub {
                                    BarnOwl::Module::AIM::cmd_aimlogin($cmd, $user, @_);
                                });
    } else {
        my $oscar = Net::OSCAR->new();
        $oscar->set_callback_signon_done(
            sub {
                BarnOwl::admin_message('AIM',
                                       'Logged in to AIM as ' . shift->screenname);
            });
        $oscar->set_callback_im_in(
            sub { BarnOwl::Module::AIM::on_im_in(@_) });
        $oscar->set_callback_connection_changed(
            sub { BarnOwl::Module::AIM::on_connection_changed(@_) });
        $oscar->set_callback_error(
            sub { BarnOwl::Module::AIM::on_error(@_) });

        $oscar->signon(
            screenname => $user,
            password => $pass
            );
        push @oscars, $oscar;
    }
}

sub cmd_aimwrite {
    my ($cmd, $recipient) = @_;
    BarnOwl::start_edit_win(join(' ', @_), sub {
            my ($body) = @_;
            my $oscar = get_oscar();
            my $sender = get_screenname($oscar);
            $oscar->send_im($recipient, $body);
            BarnOwl::queue_message(BarnOwl::Message->new(
                    type => 'AIM',
                    direction => 'in',
                    sender => $sender,
                    origbody => $body,
                    away => 0,
                    body => zformat($body, 0),
                    recipient => $recipient,
                    replycmd =>
                        "aimwrite -a $sender $recipient",
                    replysendercmd =>
                        "aimwrite -a $sender $recipient",
            ));
    });
}

BarnOwl::new_command(aimlogin => \&cmd_aimlogin, {});
BarnOwl::new_command(aimwrite => \&cmd_aimwrite, {});

### helpers ###

sub zformat($$) {
    # TODO subclass HTML::Parser
    my ($message, $is_away) = @_;
    if ($is_away) {
        return BarnOwl::boldify('[away]') . " $message";
    } else {
        return $message;
    }
}

sub get_oscar() {
    if (scalar @oscars == 0) {
        die "You are not logged in to AIM."
    } elsif (scalar @oscars == 1) {
        return $oscars[0];
    } else {
        my $m = BarnOwl::getcurmsg();
        if ($m && $m->type eq 'AIM') {
            for my $oscar (@oscars) {
                return $oscar if ($oscar->screenname eq $m->recipient);
            }
        }
    }
    die('You must specify an account with -a');
}

sub get_screenname($) {
# TODO qualify realm
    return shift->screenname;
}

1;

# vim: set sw=4 et cin:
