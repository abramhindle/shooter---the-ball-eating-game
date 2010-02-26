=pod

=head1 NAME Shooter.pl

A quick game to demonstrate the new SDL perl api for Toronto Perl Mongers, Feb 25, 2010.

=head2 AUTHOR 

Kartik Thakore

=head2 USAGE

This SDL perl requires the latest versions of SDL_gfx 2.0.20, Alien::SDL and SDL::Perl.

To get the latest versions of SDL you can use Alien::SDL 0.8.0 to get it for you.

 Click Download Source http://github.com/kthakore/Alien_SDL/
 Extract it
 perl Build.PL 
 # Linux select option to build from sources (Source code build SDL-1.2.14 + SDL_(image|mixer|ttf|net|gfx))
 # For windows use the experimental binaries SDL 1.2.14
 perl Build
 perl Build install

Also download 

 Click Download Source http://github.com/kthakore/SDL_perl/tree/redesign
 Extract it 
 perl Build.PL; perl Build; perl Build install

To run the script run this
 perl Shooter.pl

=cut

use strict;
use warnings;

use SDL;
use SDL::Video;
use SDL::Surface;
use SDL::Rect;
use SDL::Events;
use SDL::Event;
use SDL::Time;
use SDL::Color;
use SDL::GFX::Primitives;
use Data::Dumper;
use Carp;

#Initing video
#Die here if we cannot make video init
croak 'Cannot init video ' . SDL::get_error()
  if ( SDL::init(SDL_INIT_VIDEO) == -1 );

#Make our display window
#This is our actual SDL application window
my $app = SDL::Video::set_video_mode( 800, 600, 32, SDL_SWSURFACE );

croak 'Cannot init video mode 800x600x32: ' . SDL::get_error() if !($app);

#Some global variables used thorugh out the game
my $app_rect = SDL::Rect->new( 0, 0, 800, 600 );
my $fps = 30;

# The surface of the background
my $bg_surf = init_bg_surf($app);

# The actual particles that we see bouncing around
# particles are defined as hashes
my $particles = [];

#The shots we have made in each level
my @shots;

#Our level counter
my $level = 1;

my $quit = 0;

#continue until we see the $quit flag turn on that way we grace fully exit
while ( !$quit ) {

    #START our level

    my $player = create_player();

    $particles = [];    #Empty our particles new level

    @shots = ();        #Empty the shots we may have

    #Make some random particles with random velocities
    make_rand_particle($particles) foreach ( 0 .. $level );

    # Get an event object to snapshot the SDL event queue
    my $event = SDL::Event->new();

    # SDL time is recorded in ticks,
    # Ticks are the  milliseconds since the SDL library was loaded into memory
    my $time = SDL::get_ticks();

    # This is our level continue flag
    my $cont = 1;

    # Init some level globals for time calculations
    my ( $dt, $t, $accumulator, $cur_time ) = ( 0.4, 0, 0, SDL::get_ticks() );

    #Keep a copy of the cur_time for Frames per Rate calculations
    my $init_time = $cur_time;

    #Keep a count of number of frames
    my $frames = 0;

    #Our level game loop
    while ( $cont && !$quit ) {

        while ( SDL::Events::poll_event($event) )
        {    #Get all events from the event queue in our event

            #If we have a quit event i.e click on [X] trigger the quit flage
            if ($event->type == SDL_QUIT)
            {
                $quit = 1 
            }
            elsif ( $event->type == SDL_MOUSEBUTTONDOWN )
            {    #If it was a mouse button down event
                ##Check mouse and get its status
                check_mouse( SDL::Events::get_mouse_state() , $player );
            }

        }

        #Get a new time for use now
        my $new_time = SDL::get_ticks();

        #Check out how much time we have lost in calculations
        my $delta_time = $new_time - $cur_time;

        #if our delta_time is too fast we can skip this time
        #or we will have jitters in our animation
        next if ( $delta_time <= 0.0 );

        #set our new cur_time for the next calulation of delta time
        $cur_time = $new_time;

       #accumulate our delta_time. This is like our queue for back log animation
        $accumulator += $delta_time;

        # release the time in $dt amount of time so we have smooth animations
        while ( $accumulator >= $dt && !$quit ) {

            # update our particle locations base on dt time
            # (x,y) = dv*dt
            iterate_step($dt, $player );

            #dequeue our time accumulator
            $accumulator -= $dt;

            #update how much real time we have animated
            $t += $dt;

        }

        #Checkout our frames per seconds

        my $fps = $frames / ( ( SDL::get_ticks() - $init_time ) / 1000 );

        #If we are updating too fast we slow down
        #This way the X Draws don't kill our user's computer
        while ( $fps > 30 && !$quit ) {
            $fps = $frames / ( ( SDL::get_ticks() - $init_time ) / 1000 );
            SDL::delay(10);

        }

        #If our fps starts to suffer we update our $dt,
        #this way more movement for less time
        if ( $fps < ( 30 - $dt ) ) {
            $dt += ( 30 - $fps ) * 0.1;
        }

        #Update our view and count our frames
        draw_to_screen( $fps, $level, $player );
        $frames++;

        # Check if we have won this level!
        $cont = check_win($init_time);

    }

}

# Calculate the new velocities
sub iterate_step {
    my ($dt, $player) = @_;

    foreach my $p ( @{$particles} ) {
        $p->{x} += $p->{vx} * $dt;    # Make a new x from the dt given
        $p->{y} += $p->{vy} * $dt;    # Make a new y from the dt given

        # Bounce our velocities components if we are going off the screen
        $p->{vx} *= -1
          if $p->{x} > ( $app->w - ( $p->{m} / 2 ) ) && $p->{vx} > 0;
        $p->{vy} *= -1
          if $p->{y} > ( $app->h - ( $p->{m} / 2 ) ) && $p->{vy} > 0;
        $p->{vx} *= -1 if $p->{x} < ( 0 + ( $p->{m} / 2 ) ) && $p->{vx} < 0;
        $p->{vy} *= -1 if $p->{y} < ( 0 + ( $p->{m} / 2 ) ) && $p->{vy} < 0;

        # If our particle some how makes it to less then 0
        # move it into the viewable area
        $p->{x} = 0 if $p->{x} < 0;
        $p->{y} = 0 if $p->{y} < 0;
    }

    {
        # move our dude
        my $player_speed = player_speed($player);
        my ($mx,$my) = mouse_x_y();
        my $dx = $mx - $player->{x};
        my $dy = $my - $player->{y};
        my $dxps = $dx + $dy;
        my $ndx =   (abs($dxps) < 0.01)?0:($dx/$dxps);#  ($dx + $dy); # 0 error
        my $ndy =   (abs($dxps) < 0.01)?0:($dy/$dxps);#($dx + $dy); # 0 error
        my $ddx = $dt * $player_speed * $ndx;
        my $ddy = $dt * $player_speed * $ndy;
        $player->{x} += $ddx;
        $player->{x} += $ddy;
    }
}

# Create a background surface once so we
# Can keep using it as many times as we need
sub init_bg_surf {
    my $app = shift;
    my $bg =
      SDL::Surface->new( SDL_SWSURFACE, $app->w, $app->h, 32, 0, 0, 0, 0 );

    SDL::Video::fill_rect( $bg, $app_rect,
        SDL::Video::map_RGB( $app->format, 60, 60, 60 ) );

    SDL::Video::display_format($bg);
    return $bg;
}

# Check if we are done this level
sub check_win {
    my $init_time = shift;
    if ( $#{$particles} < 0 ) {
        my $secs_to_win = ( SDL::get_ticks() - $init_time / 1000 );
        my $str         = sprintf( "Level %d completed in : %2d millisecs !!!",
            $level, $secs_to_win );
        SDL::GFX::Primitives::string_color(
            $app,
            $app->w / 2 - 150,
            $app->h / 2 - 4,
            $str, 0x00FF00FF
        );

        $level++;
        SDL::Video::flip($app);
        SDL::delay(1000);
        return 0;

    }
    return 1;
}

sub mouse_x_y {
    my ($click,$x,$y) = SDL::Events::get_mouse_state();
    my @a =  ($x,$y);
    return @a;
}

# Check if the mouse hit or misses
sub check_mouse {
    my ($click,$x,$y,$player) = @_;
    # A hash to simplify accessing the mouse
    my $mouse = { click => $click, x => $x, y => $y };

    # If we have a click
    if ( $mouse->{click} ) {
        my $count_part = $#{$particles}; # Count the number of particles we have
        foreach ( 0 .. $count_part ) {
            my $p = @{$particles}[$_];
            next if !$p;    # If the particle has been splice out don't continue

           # Check if our mouse rectangle collides with the particle's rectangle
            if (   ( $mouse->{x} - 10 < $p->{x} + $p->{m} )
                && ( $mouse->{x} + 10 > $p->{x} )
                && ( $mouse->{y} - 10 < $p->{y} + $p->{m} )
                && ( $mouse->{y} + 10 > $p->{y} ) )
            {

                #We got that sucker!!
                #Get rid of the particle for us
                splice( @{$particles}, $_, 1 );
                $player->{radius}++;
                # We are done no more particles left lets get outta here
                return if $#{$particles} == -1;

            }
            else {

           #Crap we missed the guy
           #Make a rectangle there to remind us of our horrible horrible failure
                push @shots, SDL::Rect->new( $mouse->{x}, $mouse->{y}, 2, 2 );

            }
        }

    }

}

#Gets a random color for our particle
sub rand_color {
    my $r = rand( 0x100 - 0x44 ) + 0x44;
    my $b = rand( 0x100 - 0x44 ) + 0x44;
    my $g = rand( 0x100 - 0x44 ) + 0x44;

    return ( 0x000000FF | ( $r << 24 ) | ( $b << 16 ) | ($g) << 8 );

}

# Make an initail surface for the particles
# so we only use it once
sub init_particle_surf {
    my $size = shift;

    #make a surface based on the size
    my $particle =
      SDL::Surface->new( SDL_SWSURFACE, $size + 15, $size + 15, 32, 0, 0, 0,
        255 );

    SDL::Video::fill_rect(
        $particle,
        SDL::Rect->new( 0, 0, $size + 15, $size + 15 ),
        SDL::Video::map_RGB( $app->format, 60, 60, 60 )
    );

    #draw a circle on it with a random color
    SDL::GFX::Primitives::filled_circle_color( $particle, $size / 2, $size / 2,
        $size / 2 - 2,
        rand_color() );

    SDL::GFX::Primitives::aacircle_color( $particle, $size / 2, $size / 2,
        $size / 2 - 2, 0x000000FF );
    SDL::GFX::Primitives::aacircle_color( $particle, $size / 2, $size / 2,
        $size / 2 - 1, 0x000000FF );

    SDL::Video::display_format($particle);
    my $pixel = SDL::Color->new( 60, 60, 60 );
    SDL::Video::set_color_key( $particle, SDL_SRCCOLORKEY, $pixel );

    return $particle;
}

# mutates a player
sub init_player_surf {
    my $player = shift;
    my $size = 2*$player->{radius};
    #make a surface based on the size
    my $particle =
      SDL::Surface->new( SDL_SWSURFACE, $size, $size, 32, 0, 0, 0,
        255 );

    SDL::Video::fill_rect(
        $particle,
        SDL::Rect->new( 0, 0, $size, $size),
        SDL::Video::map_RGB( $app->format, 60, 60, 60 )
    );

    #draw a circle on it with a random color
    SDL::GFX::Primitives::filled_circle_color( $particle, $size / 2, $size / 2,
        $size / 2 - 2,
        $player->{color} );

    SDL::GFX::Primitives::aacircle_color( $particle, $size / 2, $size / 2,
        $size / 2 - 2, 0x000000FF );
    SDL::GFX::Primitives::aacircle_color( $particle, $size / 2, $size / 2,
        $size / 2 - 1, 0x000000FF );

    SDL::Video::display_format($particle);
    my $pixel = SDL::Color->new( 60, 60, 60 );
    SDL::Video::set_color_key( $particle, SDL_SRCCOLORKEY, $pixel );
    $player->{surf} = $particle;
    return $player;
}



# The final update that is drawn to the screen
sub draw_to_screen {
    my ( $fps, $level, $player ) = @_;

    #Blit the back ground surface to the window
    SDL::Video::blit_surface(
        $bg_surf, SDL::Rect->new( 0, 0, $bg_surf->w, $bg_surf->h ),
        $app,     SDL::Rect->new( 0, 0, $app->w,     $app->h )
    );

    # Draw out all our failures to hit the particles

    foreach ( 0 .. $#shots ) {

        SDL::Video::fill_rect( $app, $shots[$_],
            SDL::Video::map_RGB( $app->format, 0, 0, 0 ) );

    }

    #make a string with the FPS and level
    my $pfps = sprintf( "FPS:%.2f Level:%2d", $fps, $level );

    #write our string to the window
    SDL::GFX::Primitives::string_color( $app, 3, 3, $pfps, 0x00FF00FF );

    #Draw each particle
    draw_particles();

    draw_player($player);

    #Update the entire window
    #This is one frame!
    SDL::Video::flip($app);
}

# Draw the particles on the screen
sub draw_particles {
    foreach my $p ( @{$particles} ) {

        my $new_part_rect = SDL::Rect->new( 0, 0, $p->{m}, $p->{m} );

        #Blit the particles surface to the app in the right location
        SDL::Video::blit_surface(
            $p->{surf},
            $new_part_rect,
            $app,
            SDL::Rect->new(
                $p->{x} - ( $p->{m} / 2 ), $p->{y} - ( $p->{m} / 2 ),
                $app->w, $app->h
            )
        );

    }
}


sub draw_player {
    my ($p) = @_;
    my $m = int(2*$p->{radius});
    my $new_part_rect = SDL::Rect->new( 0, 0, $m, $m );
    #Blit the particles surface to the app in the right location
    SDL::Video::blit_surface(
                             $p->{surf},
                             $new_part_rect,
                             $app,
                             SDL::Rect->new(
                                            int($p->{x} -  $p->{radius} ), 
                                            int($p->{y} -  $p->{radius} ),
                                            $app->w, $app->h
                                           )
                            );
}


# Make a random particle
sub make_rand_particle {

    my $particles = shift;

    my $t = $#{$particles};
    $t = 0 if $t == -1;

    #get a random size of our particle
    my $size = int( rand(36) + 20 );

    my $particle = {

        #randomly place the particle in our app's w and h
        x => rand( $app->w - ( $size / 2 ) ),
        y => rand( $app->h - ( $size / 2 ) ),
        vx => rand(1) - rand(1),    #Get a random X and Y velocity component
        vy => rand(1) - rand(1),
        m  => $size,                # The mass or size of the particle
        n  => $t,                   # The number the particle is
    };

    #Make a surface for our particle
    $particle->{surf} = init_particle_surf( $particle->{m} );
    push @{$particles}, $particle;

}

sub create_player {
    my %hash = @_;
    my $player = {
        player => 1,
        x => $hash{x} || 0,
        y => $hash{y} || 0,
        radius => $hash{radius} || 10,
        color => $hash{color} || rgb_color(255,255,255),
    };
    #make the surface
    return init_player_surf($player);
}

sub player_speed {
    my ($player) = @_;
    return 100 - max(0,10*($player->{radius} - 10));
}



sub rgb_color {
    my ($r,$g,$b) = @_;
    return ( 0x000000FF | ( $r << 24 ) | ( $b << 16 ) | ($g) << 8 );
}

sub max {
    my $max = shift;
    while(@_) {
        my $t = shift;
        $max = ($t > $max)?$t:$max;
    }
    return $max;
}

# Todo
#   draw a player, he moves towards the mouse at a certain speed
#     speed decreases as he eats more
#     radius increases as he eats more
