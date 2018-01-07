package Treex::PML::Backend::UD;

=head1 Treex::PML::Backend::UD

=cut

use warnings;
use strict;

use Treex::PML::IO qw{ open_backend close_backend };

sub test {
    my ($filename, $encoding) = @_;
    open my $in, '<', $filename or die "$filename: $!";
    my $first_line = <$in>;

    return 1 if $first_line =~ /^# (?:new(?:doc|par)\s+id|sent_id|text) = /;
    return
}


sub read {
    my ($fh, $doc) = @_;
    my $root;
    while (<$fh>) {
        if (/^#\s*sent_id\s=\s*(\S+)/) {
            my $sent_id = $1;
            $doc->append_tree(
                $root = 'Treex::PML::Node'->new({id => $sent_id}),
                $doc->lastTreeNo);
        } elsif (/^#\s*text\s*=\s*(.*)/) {
            $root->{text} = $1;
        } elsif (/^$/) {
            _create_structure($root);
        } elsif (/^#/) {
        } else {
            my ($n, $form, $lemma, $upos, $xpos, $feats, $head, $deprel,
                $deps, $mis) = split /\t/;
            next if $n =~ /-/;  # TODO: multiword

            'Treex::PML::Node'->new({
                form => $form,
                ord => $n,
                head => $head})
            ->paste_on($root, 'ord');
        }
    }
}


sub write {
    my ($fh, $doc) = @_;
}


sub _create_structure {
    my ($root) = @_;
    my %ord = map +($_->{ord} => $_), $root->children;
    for my $node ($root->children) {
        $node->cut->paste_on($ord{ $node->{head} } || $root, 'ord');
    }
}

__PACKAGE__
