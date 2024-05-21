# -*- cperl -*-
{   package UD;

    BEGIN { import TredMacro }

    use strict;

    unshift @TrEd::Config::open_types, [
        'Universal Dependencies',
        [ '.conllu' ],
    ] unless grep $_ eq 'Universal Dependencies',
             @{ $TrEd::Config::open_types[0] };

    our $previous_stylesheet;

    my $ud_backend = 'UD';
    AddBackend(Treex::PML::ImportBackends($ud_backend))
        unless grep $ud_backend eq $_, Backends();

    push @TredMacro::AUTO_CONTEXT_GUESSING, sub {
        my ($hook) = @_;
        my $resuming = ($hook eq 'file_resumed_hook');
        my $current = CurrentContext();
        return detect() ? __PACKAGE__ : ()
    };


    sub detect {
        return (((PML::SchemaName() || "") eq 'ud') ? 1 : 0)
    }


    sub file_close_hook {
        $previous_stylesheet = GetCurrentStylesheet();
        return
    }


    sub allow_switch_context_hook {
        return 'stop' unless detect();
    }


    sub switch_context_hook {
        if (STYLESHEET_FROM_FILE() eq GetCurrentStylesheet()) {
            my $stylesheet = $previous_stylesheet // 'UD';
            SetCurrentStylesheet($stylesheet);
        }
        Redraw() if GUI();
    }


    sub get_value_line_hook {
        my ($doc, $tree_no) = @_;
        my $tree = $doc->tree($tree_no);
        my %by_ord;
        my %mw;
        if ($tree->{multiword}) {
            %by_ord = map { $_->{ord}, $_ } $tree->descendants;
            @mw{ ListV($_->{nodes}) } = () for ListV($tree->{multiword});
        }
        my @nodes = sort {  # by_ord not needed, we grep only int ords.
            ($a->{ord} // $a->{nodes}[0])
            <=>
            ($b->{ord} // $b->{nodes}[0])
        } ListV($tree->{multiword}), grep $_->{ord} !~ /\./
                                          && ! exists $mw{ $_->{ord} },
                                     $tree->descendants;

        return [ map { [ $_->{form},
                         $_->{ord} ? $_ : @by_ord{ ListV($_->{nodes}) } ],
                       ((grep 'SpaceAfter=No' eq $_, ListV($_->{misc}))
                           ? () : [ ' ' ])
                     } @nodes ]
    }


    sub by_ord {
        (int($a->{ord}) <=> int($b->{ord}))
        ||
        (($a->{ord} =~ /\.([0-9]+)/)[0] <=> ($b->{ord} =~ /\.([0-9]+)/)[0])
    }


    sub get_nodelist_hook {
        my ($doc, $treeno, $current, $show) = @_;
        my $tree = $doc->tree($treeno);
        return [[$root, sort by_ord $tree->descendants],
                $current]
    }

    sub insert_null {
        ChangingFile(1);
        my $ord = [split /\./, $this->{ord}];
        $_ //= 0 for @$ord[0, 1];
        ++$ord->[1];
        my @renumber = grep int($_->{ord}) == $ord->[0]
                            && ($_->{ord} =~ /\.([0-9]+)$/)[0] >= $ord->[1],
                       $root->descendants;
        for my $ref ($root->descendants) {
            for my $dep (ListV($ref->{deps})) {
                for my $ref_r (grep $_->{ord} eq $dep->content, @renumber) {
                    my @n = split /\./, $dep->content;
                    $dep->set_content(join '.', $n[0], $n[1] + 1);
                }
            }
        }
        for my $r (@renumber) {
            my @n = split /\./, $r->{ord};
            $r->{ord} = join '.', $n[0], $n[1] + 1;
        }
        # Null nodes con't be in ranges, no need to check multiword.

        my $new = PlainNewSon($this);
        $new->set_type_by_name($root->type->schema, 'ud.node.type');
        $new->{ord} = join '.', @$ord;
        $new->{$_} = '_' for qw( deprel lemma upostag );
        EditAttribute($new, 'form');
    }


    {   my %DISPATCH = (
            deprel  => \&edit_deprel,
        );
        sub do_edit_attr_hook {
            my ($attr, $node) = @_;
            return unless $attr =~ /^(?:deprel|upostag|lemma|feats)$/;

            $DISPATCH{$attr}->($node) if exists $DISPATCH{$attr};
        }
    }


    sub edit_this_upos {
        ChangingFile(0);
        EditAttribute($this, 'upostag');
    }


    sub edit_this_lemma {
        ChangingFile(0);
        EditAttribute($this, 'lemma');
    }


    sub edit_this_feats {
        ChangingFile(0);
        EditAttribute($this, 'feats');
    }


    sub edit_this_deprel {
        edit_deprel($this);
    }


    {   my @deprels = qw( acl advcl advmod amod appos aux case cc
                          ccomp clf compound conj cop csubj dep det
                          discourse dislocated expl fixed flat
                          goeswith iobj list mark nmod nsubj nummod
                          obj obl orphan parataxis punct reparandum
                          root vocative xcomp );

        sub edit_deprel {
            my ($node) = @_;

            my $dialog = $grp->toplevel->DialogBox(
                -title   => 'Deprel',
                -buttons => ['OK', 'Cancel']);
            $dialog->bind('<Escape>' => sub {
                              $dialog->{selected_button} = 'Cancel' });
            my $list = $dialog->add(
                BrowseEntry => -label    => 'deprel',
                               -variable => \(my $choice = $node->{deprel})
            )->pack;
            $list->insert(end => $_) for @deprels;
            my $reply = $dialog->Show;
            if ('OK' eq $reply) {
                my $old_deprel = $node->{deprel};
                $node->{deprel} = $choice;
                $node->{deps} = List(map {
                    ($_->content == $node->parent->{ord}
                     && $_->{func} eq $old_deprel)
                        ? _create_container($_->content, $choice)
                        : $_
                } ListV($node->{deps}));
                ChangingFile(1);
                Redraw();
            }
            return 'stop'
        }
    }


    sub node_release_hook {
        my ($node, $target, $mod) = @_;
        ChangingFile(0);
        return unless $target;

        my $parent = $node->parent;
        if (defined $mod && $mod =~ /^Control(?:-[23])?$/) {
            if (grep $_->content == $target->{ord}, ListV($node->{deps})) {
                ChangingFile(1);
                $node->{deps} = List(grep $_->content != $target->{ord},
                                     ListV($node->{deps}));
            } else {
                my $func = QueryString(
                    'Enhanced Dependency',
                    'deprel',
                    ($target == $parent) ? $node->{deprel} : "");
                return 'stop' unless length $func;

                ChangingFile(1);
                AddToList($node, 'deps',
                          _create_container($target->{ord}, $func));
            }
        } else {
            return if $target == $parent;

            my $with_enhanced = ! (defined $mod && $mod eq 'Shift');
            my @deps = ($with_enhanced
                            ? _create_container($target->{ord},
                                                $node->{deprel})
                            : (),
                        grep $_->content != $parent->{ord}
                             && $_->content != $target->{ord},
                        ListV($node->{deps}));
            delete $node->{deps};
            $node->{deps} = List(@deps) if @deps;
            CutPaste($node, $target);
            ChangingFile(1);
        }
        Redraw();
        return 'stop'
    }


    {   my @colours = qw( plum red orange pink magenta violet );

        sub after_redraw_hook {
            return unless $root->{multiword};

            my %by_ord = map +( $_->{ord} => $_ ), $root->descendants;
            my @groups = map [ @by_ord{ @{ $_->{nodes} } } ],
                     @{ $root->{multiword} };
            TrEd::NodeGroups::draw_groups(
                $grp,
                \@groups,
                { colors => [ (@colours) x ( 1 + @groups / @colours ) ] }
            );
        }
    }


    sub _create_container {
        my ($ord, $func) = @_;
        return 'Treex::PML::StandardFactory'->createContainer(
            $ord, {func => $func})
    }
}
