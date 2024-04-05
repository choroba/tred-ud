package Treex::PML::Backend::UD;

=head1 NAME

Treex::PML::Backend::UD - TrEd backend to load and save UD files directly

=cut

use warnings;
use strict;

use Treex::PML::IO qw{ open_backend close_backend };

sub test {
    my ($filename, $encoding) = @_;
    open my $in, '<', $filename or die "$filename: $!";
    while (<$in>) {
        return unless /^#/;
        return 1 if /^# (?:new(?:doc|par)\s+id|sent_id|text)(?: =)? ./;
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

        if (/^#\s*sent_id(?:\s*=\s*|\s+)(\S+)/) {
            my $sent_id = $1;
            substr $sent_id, 0, 0, 'PML-' if $sent_id !~ /^PML-/;
            $root->{id} = $sent_id;
            $doc->append_tree($root, $doc->lastTreeNo);

        } elsif (/^#\s*text\s*=\s*(.*)/) {
            $root->{text} = $1;

        } elsif (/^$/) {
            _create_structure($root);
            undef $root;

        } elsif (/^#\s+new(doc|par)(?:\s+id = (.*))?/) {
            $root->{$1} = $2;

        } elsif (/^#/) {
            $root->{comment} = 'Treex::PML::Factory'->createList([
                @{ $root->{comment} || [] }, substr $_, 1 ]);

        } else {
            my ($n, $form, $lemma, $upos, $xpos, $feats, $head, $deprel,
                $deps, $misc) = split /\t/;
            $_ eq '_' and undef $_
                for $xpos, $feats, $deps, $misc;

            $misc = 'Treex::PML::Factory'->createList(
                [ split /\|/, ($misc // "") ]);
            if ($n =~ /-/) {
                _create_multiword($n, $root, $misc, $form);
                next
            }

            $feats = _create_feats($feats);
            $deps = [ map {
                my ($parent, $func) = split /:/;
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
        _serialize_doc_and_par($root, $fh);

        $root->{id} =~ s/^PML-//;
        print {$fh} "# sent_id = ", $root->{id}, "\n";
        print {$fh} "# text = ", $root->{text}, "\n" if exists $root->{text};
        print {$fh} map "#$_\n", @{ $root->{comment} };
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


sub _serialize_doc_and_par {
    my ($root, $fh) = @_;
    for my $attr (qw( doc par )) {
        if (exists $root->{$attr}) {
            print {$fh} "# new$attr";
            print {$fh} ' id = ', $root->{$attr} if length $root->{$attr};
            print {$fh} "\n";
        };
    }
}


sub _serialize_deps {
    my ($deps) = @_;
    return '_' unless @$deps;
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
