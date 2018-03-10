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

    my $ud_backend = 'Treex::PML::Backend::UD';
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
        my @nodes = sort { $a->{ord} <=> $b->{ord} } $tree->descendants;

        return [ map { [ $_->{form}, $_ ],
                       ((grep 'SpaceAfter=No' eq $_, ListV($_->{misc}))
                           ? () : [ ' ' ])
                     } @nodes ]
    }


    sub get_nodelist_hook {
        my ($doc, $treeno, $current, $show) = @_;
        my $tree = $doc->tree($treeno);
        return [[$root, sort { $a->{ord} <=> $b->{ord} } $tree->descendants],
                $current]
    }


    {   my @deprels = qw( acl advcl advmod amod appos aux case cc
                          ccomp clf compound conj cop csubj dep det
                          discourse dislocated expl fixed flat
                          goeswith iobj list mark nmod nsubj nummod
                          obj obl orphan parataxis punct reparandum
                          root vocative xcomp );

        sub do_edit_attr_hook {
            my ($attr, $node) = @_;
            return unless 'deprel' eq $attr;

            my $dialog = $grp->toplevel->DialogBox(
                -title   => 'Deprel',
                -buttons => ['OK', 'Cancel']);
            my $list = $dialog->add(
                BrowseEntry => -label    => 'deprel',
                               -variable => \(my $choice = $node->{deprel}))->pack;
            $list->insert(end => $_) for @deprels;
            my $reply = $dialog->Show;
            if ('OK' eq $reply) {
                $node->{deprel} = $choice;
                Redraw();
            }
            return 'stop'
        }
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
}
