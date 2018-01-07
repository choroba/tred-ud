# -*- cperl -*-
{   package UD;

    warn "ud.inc\n\n\n";

    BEGIN { import TredMacro }

    use strict;

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
}
