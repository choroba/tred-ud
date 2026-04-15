package Treex::PML::Backend::UD;

=head1 NAME

Treex::PML::Backend::UD - TrEd backend to load and save UD files directly

=cut

use warnings;
use strict;

use Treex::PML::IO qw{ open_backend close_backend };

use constant {ID   => \'id',
              TEXT => \'text',
              DOC  => \'doc',
              PAR  => \'par'};

sub test {
    my ($filename, $encoding) = @_;
    my $in = open_backend($filename, 'r', $encoding) or die "$filename: $!";
    while (<$in>) {
        return unless /^#/;
        return 1 if /^# (?:new(?:doc|par)\s+id|text)(?: =)? ./;
    }
}


sub read {
    my ($fh, $doc) = @_;
    my $schema = 'Treex::PML::Factory'->createPMLSchema({
        filename => 'ud_schema.xml',
        use_resources => 1});
    $doc->changeMetaData('schema', $schema);

    my $root;
    while (<$fh>) {
        chomp;
        if (/^#/ && ! $root) {
            $root = 'Treex::PML::Factory'->createTypedNode(
                    'ud.sent.type', $schema, {}
            );
        }

        if (/^#/) {
            $root->{comments} //= 'Treex::PML::Factory'->createSeq;

            if (/^#\s*sent_id(?:\s*=\s*|\s+)(\S+)/) {
                my $sent_id = $1;
                substr $sent_id, 0, 0, 'PML-' if $sent_id !~ /^PML-/;
                $root->{id} = $sent_id;
                $doc->append_tree($root, $doc->lastTreeNo);
                $_ = ID;

            } elsif (/^#\s*text\s*=\s*(.*)/) {
                $root->{text} = $1;
                $_ = TEXT;

            } elsif (/^#\s+new(doc|par)(?:\s+id = (.*))?/) {
                $root->{$1} = $2;
                $_ = ('doc' eq $1) ? DOC : PAR;

            } else {
                substr $_, 0, 1, "";
            }
            $root->{comments}->push_element(ref ? (special => $$_)
                                                : (comment => $_));

        } elsif (/^$/) {
            _create_structure($root);
            undef $root;

        } else {
            my ($n, $form, $lemma, $upos, $xpos, $feats, $head, $deprel,
                $deps, $misc) = split /\t/;
            ($_ // '_') eq '_' and undef $_
                for $xpos, $feats, $deps, $misc;

            $misc = 'Treex::PML::Factory'->createList(
                [ split /\|/, ($misc // "") ]);
            if ($n =~ /-/) {
                _create_multiword($n, $root, $misc, $form);
                next
            }

            $feats = _create_feats($feats);
            $deps = [ map {
                my ($parent, $func) = split /:/, $_, 2;
                'Treex::PML::Factory'->createContainer($parent,
                                                       {func => $func});
            } split /\|/, ($deps // "") ];

            'Treex::PML::Factory'->createTypedNode('ud.node.type', $schema,
                {
                    form    => $form,
                    lemma   => $lemma,
                    ord     => $n,
                    deprel  => $deprel,
                    upostag => $upos,
                    xpostag => $xpos,
                    feats   => $feats,
                    deps    => 'Treex::PML::Factory'->createList($deps),
                    misc    => $misc,
                    head    => $head}
                )->paste_on($root, 'ord');
        }
    }
    if ($root) {
        _create_structure($root);
        warn "Emtpy line missing at the end of input\n";
    }
}


sub write {
    my ($fh, $doc) = @_;
    for my $root ($doc->trees) {

        $root->{id} =~ s/^PML-//;
        for my $c ($root->{comments}->elements) {
            print {$fh} '#', _serialize_comment($c, $root), "\n";
        }
        for my $node (sort { $a->{ord} <=> $b->{ord} } $root->descendants) {
            if (my ($mw_idx)
                = grep $root->{multiword}[$_]{nodes}[0] == $node->{ord},
                  0 .. $#{ $root->{multiword} }
            ) {
                my $mw = $root->{multiword}[$mw_idx];
                print {$fh} join("\t",
                                 "$mw->{nodes}[0]-$mw->{nodes}[-1]",
                                 $mw->{form},
                                 ('_') x 7,
                                 _serialize_misc($mw->{misc})
                             ), "\n";
            }
            print {$fh} join "\t",
                @$node{qw{ ord form lemma upostag }},
                $node->{xpostag} // '_',
                join('|',
                     map "$_->{name}=$_->{value}", @{ $node->{feats} }
                ) || '_',
                $node->parent->{ord} || '0',
                $node->{deprel} || '_',
                _serialize_deps($node->{deps}),
                _serialize_misc($node->{misc}),
            ;
            print {$fh} "\n";
        }
        print {$fh} "\n";
    }
    return 1
}


{   my %PREFIX = (id => 'sent',
                  par => 'newpar',
                  doc => 'newdoc',
                  text => 'text');
    my %ID_SUFFIX = (id => '_', par => ' ', doc => ' ');
    sub _serialize_comment {
        my ($c, $root) = @_;
        return $c->[1] if 'comment' eq $c->[0];

        $c = $c->[1];
        return " $PREFIX{$c}"
            . (length($root->{$c})
               ? (exists $ID_SUFFIX{$c} ? "$ID_SUFFIX{$c}id" : "")
                 . " = $root->{$c}"
               : "")
    }
}

sub _serialize_misc {
    my ($misc) = @_;
    return join('|', @{ $misc }) || '_'
}


sub _create_feats {
    my ($string) = @_;
    return 'Treex::PML::Factory'->createList([])
        unless defined $string && length $string;
    my @feats;
    for (split /\|/, $string) {
        my ($name, $value) = split /=/, $_, 2;
        push @feats, 'Treex::PML::Factory'->createStructure(
            { name => $name, value => $value });
    }
    return 'Treex::PML::Factory'->createList(\@feats)
}


sub _create_multiword {
    my ($n, $root, $misc, $form) = @_;
    my ($from, $to) = split /-/, $n;
    $root->{multiword} = 'Treex::PML::Factory'->createList([
        @{ $root->{multiword} || [] },
        'Treex::PML::Factory'->createStructure(
            { nodes => 'Treex::PML::Factory'->createList([ $from .. $to ]),
              misc => $misc,
              form => $form}
        )
    ]);
}

sub _serialize_deps {
    my ($deps) = @_;
    return '_' unless @{ $deps // [] };
    return join '|',
           map "$_->{'#content'}:$_->{func}",
           sort { $a->{'#content'} <=> $b->{'#content'} }
           @$deps;
}


sub _create_structure {
    my ($root) = @_;
    my %ord = map +($_->{ord} => $_), $root->children;
    for my $node ($root->children) {
        $node->cut->paste_on($ord{ $node->{head} || $root } || $root, 'ord');
    }
}

__PACKAGE__
