############################################################
# Magic Maze - a simple and low-tech monster-bashing maze game.
# Copyright (C) 2004-2013 Kent Dahl
#
# This game is FREE as in both BEER and SPEECH. 
# It is available and can be distributed under the terms of 
# the GPL license (version 2) or alternatively 
# the dual-licensing terms of Ruby itself.
# Please see README.txt and COPYING_GPL.txt for details.
############################################################

require 'gosu'

require 'magicmaze/images'
require 'magicmaze/tile'

module MagicMaze

  module Engine
    class GosuGameWindow < ::Gosu::Window

      attr_accessor :drawer, :updater, :input_handler

      def initialize(parent, xsize, ysize, fullscreen, delay)
        super(xsize, ysize, fullscreen, delay)
        @parent = parent
      end

      def needs_cursor?
        true
      end

      def draw
        @drawer.draw if @drawer
      end

      def update
        @updater.update if @updater
      end

      def button_down(id)
        @input_handler.button_down(id) if @input_handler
      end


    end
  end

  ################################################
  #
  class Graphics
    include Images # Generic GFX.

    attr_reader :window

    SCREEN_IMAGES = {
      :titlescreen => 'title.png',
      :background  => 'background.png',
      :endscreen   => 'end.png',
    }

    # ##
    # # Singleton graphics instance.
    # def self.get_graphics(options={})
    #   @graphics_instance ||= MagicMaze::Graphics.new(options)
    #   @graphics_instance
    # end

    # def self.shutdown_graphics
    #   @graphics_instance.destroy
    #   @graphics_instance = nil
    # end

    def initialize(options={})
      puts "Starting Magic Maze..."
      screen_init(options)
      early_progress
      font_init

      @progress_msg = _("Summoning") + "\n."
      early_progress

      load_background_images

      @progress_msg = _("Magic Maze") + "\n."
      early_progress

      @sprite_images = load_new_sprites || load_old_sprites 

      # show_message("Enter!")
      
      # Cached values for what is already drawn.
      @cached_drawing = Hash.new
      @delay_stats = Array.new

      puts "Graphics initialized." if DEBUG
    end


    def set_loop(game, drawer = nil, input = nil, updater = nil)
      @game = game
      @window.drawer        = drawer  || game
      @window.input_handler = input   || game
      @window.updater       = updater || game
    end

    def start_loop(game)
      set_loop(game)
      @window.show
    end

    def destroy
      if @delay_stats && @delay_stats.size.nonzero? then
        puts "Delay average: " + 
          (@delay_stats.inject(0.0){|i,j|i+j}/@delay_stats.size).to_s
        puts "Delay min/max: " + 
          @delay_stats.min.to_s + " / " + @delay_stats.max.to_s
      end
      puts "closing window..."
      @window.close
    end

    def screen_init(options)
      puts "Setting up graphics..." if DEBUG
      @xsize = FULLSCREEN[2]
      @ysize = FULLSCREEN[3]

      @delay = 100

      @window = ::MagicMaze::Engine::GosuGameWindow.new(self, @xsize, @ysize, !options[:fullscreen].nil?, @delay)
      @screen = @window

      early_progress

      early_progress
      
    end

    def draw
      @curr_bg.draw(0,0,0) if @curr_bg
    end


    # Simple progress indication before we can write etc to screen.
    def early_progress(progress=nil, flip=true, clear=true)
      @progress = progress || (@progress||0)+1
      w = SCALE_FACTOR * (64 - @progress*8)
      c = 255 - (@progress**2)
      #clear_screen if clear
      #@screen.fill_rect(@xsize-w,0, w,@ysize,
      #                  @screen.map_rgb(c,c,c))
      show_long_message(@progress_msg) if @progress_msg
      #@screen.flip if flip
    end



    def font_init
      ## Fonts
      # Free font found at: http://www.squaregear.net/fonts/ 
      fontfile = "data/gfx/fraktmod.ttf"
      fontsize = [16, 32]
      tries = 0
      
      alternate_fonts = [
        "/usr/share/fonts/truetype/isabella/Isabella.ttf",
        "/usr/share/fonts/truetype/ttf-isabella/Isabella.ttf",
        "/usr/share/fonts/truetype/Isabella.ttf"
      ]
      
      begin
        @font16 = Gosu::Font.new(@window, fontfile, fontsize.last)
        @font32 = Gosu::Font.new(@window, fontfile, fontsize.last)
      rescue => err
        # Debian font
        fontfile = alternate_fonts.shift # "/usr/share/fonts/truetype/Isabella.ttf"
        fontsize = [12, 28]
        if fontfile then 
          retry 
        else 
          raise err 
        end
      end
      @font = @font16
    end

    def load_background_images
      @background_images = {}
      SCREEN_IMAGES.each{|key, filename|
        source_image = Gosu::Image.new(@window, GFX_PATH+filename, true)
        @progress_msg += "." ; early_progress
        if SCALE_FACTOR != 1 then
          scaled_image = source_image   # TODO: Scaling...
        else
          scaled_image = source_image
        end
        
        @background_images[key] = scaled_image || source_image
      }
    end

    ##
    # reads in the old sprites from the "undocumented" format I used.
    #
    def load_old_sprites
      sprite_images = []
      File.open( GFX_PATH+'sprites.dat', 'rb'){|file|
        # First 3*256 bytes is the palette, with values ranged (0...64).
        palette_data = file.read(768) 
        if palette_data.size == 768 then
          palette = (0..255).collect{|colour|
            data = palette_data[colour*3,3]
            [data[0], data[1], data[2]].collect{|i| i*255/63}
              #((i<<2) | 3) + 3 }
          }
        end

        @sprite_palette = palette

        # Loop over 1030 byte segments, which each is a sprite.
        begin
          sprite_data = file.read(1030)
          if sprite_data && sprite_data.size==1030 then
            x = 0
            y = 0
            sprite.lock
            # The first six bytes is garbage?
            sprite_data[6,1024].each_byte{|pixel|
              sprite.put_pixel(x,y,pixel)
              x += 1 # *SCALE_FACTOR
              if x>31
                x = 0
                y += 1
              end              
            }
            sprite.unlock
            sprite.setColorKey( SDL::SRCCOLORKEY || SDL::RLEACCEL ,0)
            sprite_images << sprite.display_format
          end
        end while sprite_data
      }
      sprite_images
    end



    ##
    # Load sprites from a large bitmap. Easier to edit.
    #
    def load_new_sprites
      puts "Loading sprites..." if DEBUG
      sprite_images = Gosu::Image::load_tiles(@window, GFX_PATH + 'sprites.png', 32, 32, true)
      sprite_images
    end



    ##
    # save sprites out to bitmap
    #
    def save_old_sprites( filename = "tmpgfx" )    
    end



    #################################################
    # View specific methods


    def write_score( score )
      # return if cached_drawing_valid?(:score, score )

      text = sprintf "%9d", score   # fails on EeePC
      # text = sprintf "%09d", score # old safe one.
      rect = SCORE_RECTANGLE
      #@screen.fillRect(*rect)
      @font16.draw(text, rect[0], rect[1]-2, 1, 0.5, 0.5, 0xFFFFFFFF) 
      #write_text( text, rect[0]+2*SCALE_FACTOR, rect[1]-2*SCALE_FACTOR ) 
    end


    ##
    # Show a single line message centered in the 
    # maze view area.
    #
    def show_message( text, flip = true )
      rect = MAZE_VIEW_RECTANGLE
      #@screen.fillRect(*rect)

      tw, th = 32, 32 # @font32.text_size( text )

      x = rect[0] 
      y = rect[1]
      w = rect[2] 
      h = rect[3] 
      
      write_smooth_text(text, 
                 x + (w-tw)/2,
                 y + (h-th)/2, 
                 @font32 ) 
      #@screen.flip if flip
    end

    ##
    # Show a multi-line message centered in the
    # maze view area.
    def show_long_message( text, flip = true, fullscreen = false )
      rect = ( fullscreen ? FULLSCREEN : MAZE_VIEW_RECTANGLE)
      #@screen.fillRect(*rect)

      gth = 0
      lines = text.split("\n").collect do |line| 
        tw, th = 32, 32 # @font32.text_size( line ) 
        gth += th
        [ line, tw, th ]
      end

      x = rect[0] 
      y = rect[1]
      w = rect[2] 
      h = rect[3] 

      y_offset = y + (h-gth)/2

      lines.each do |line, tw, th|
        write_smooth_text(line, 
                          x + (w-tw)/2,
                          y_offset, 
                          @font32 )
        y_offset += th
      end

      #@screen.flip if flip
    end

    def cached_drawing_valid?(symbol, value)
      return true if value == @cached_drawing[symbol]
      @cached_drawing[symbol] = value
      false
    end

    
    ##
    # assumes life and mana are in range (0..100)
    def update_life_and_mana( life, mana )
      rect = LIFE_MANA_RECTANGLE
      col_red  = 0xFFFF0000
      col_blue = 0xFF0000FF
      draw_rectangle(rect[0], rect[1], 
                       rect[2]*life/100, rect[3]/2, 
                       col_red) # if life.between?(0,100)
      draw_rectangle(rect[0], rect[1]+rect[3]/2, 
                       rect[2]*mana/100, rect[3]/2,
                       col_blue) # if mana.between?(0,100)      
    end

    def draw_rectangle(ax,ay,w,h,col)
      bx = ax+w
      by = ay+h

      @window.draw_quad(
        ax, ay, col, 
        bx, ay, col,
        bx, by, col,
        ax, by, col,
        1 
       )
    end

    def update_inventory( inventory )
      # FIXME: return if cached_drawing_valid?(:inventory, inventory.hash )
      rect = INVENTORY_RECTANGLE
      currx = rect.first
      curry = rect[1]
      stepx = SPRITE_WIDTH / 4
      inventory.each{|obj|
        put_sprite(obj, currx, curry )
        currx += stepx
      }
    end

    def update_spells( primary, secondary )
      # return if cached_drawing_valid?(:spells, primary.hash ^ secondary.hash )

      rect1 = SPELL_RECTANGLE
      rect2 = ALT_SPELL_RECTANGLE
      put_sprite( primary, *rect1[0,2]) 
      put_sprite( secondary, *rect2[0,2]) 
    end

    def update_player( player_sprite )
      put_sprite(player_sprite, *PLAYER_SPRITE_POSITION )
    end



    ####################################
    # Experimental view updating trying 
    # to refactor and separate view logic
    # from the GameLoop as much as possible.

    def update_view_rows( center_row )
      @curr_view_y = MAZE_VIEW_RECTANGLE[1]
      VIEW_AREA_MAP_HEIGHT.times{|i| 
        yield i+center_row-VIEW_AREA_MAP_HEIGHT_CENTER
        @curr_view_y += SPRITE_HEIGHT
      }
    end
    def update_view_columns( center_column )
      @curr_view_x = MAZE_VIEW_RECTANGLE[0]
      VIEW_AREA_MAP_WIDTH.times{|i|
        yield i+center_column-VIEW_AREA_MAP_WIDTH_CENTER
        @curr_view_x += SPRITE_WIDTH
      }
    end
    def update_view_background_block( sprite_id )
      put_background( sprite_id, @curr_view_x, @curr_view_y )
    end
    def update_view_block( sprite_id )
      put_sprite( sprite_id, @curr_view_x, @curr_view_y )
    end


    ####################################
    #
    def show_help
      clear_screen

      lines = [
        '  ---++* Magic Maze Help *++---',
        'Arrow keys to move the wizard.',
        'Ctrl :-  Cast attack spell',
        'Alt :-  Cast secondary spell',
        'X / Z :- Toggle attack spell',
        'A / S :- Toggle secondary spell',
        '', # Failed for RubySDL2.0.1 and Ruby1.9.1-p1
        'Esc / Q :- Quit playing',
        'F9 / R :- Restart level',
        # '[F4]: Load game    [F5]: Save game',
        # '[S]: Sound on/off',
        'PgUp / PgDn :- Tune Volume',
        'Plus / Minus :- Tune Speed (on keypad)',
      ]
      
      y_offset = 0
      font = @font16
      lines.each{|line|
        write_smooth_text( line, 5, y_offset, font ) if line.size.nonzero? # Failed for RubySDL2.0.1 and Ruby1.9.1-p1 on empty string.
        y_offset+= font.height
      }
      
      flip
    end


    ####################################
    #
    def draw_map( player, line_by_line = true )
      return 
      map = player.location.map

      rect = MAZE_VIEW_RECTANGLE
      @screen.fillRect(*rect)
      
      if line_by_line then
        @screen.flip 
        @screen.fillRect(*rect)
      end

      map_zoom_factor = 4

      map_block_size = SPRITE_WIDTH / map_zoom_factor
      map_height = VIEW_AREA_MAP_HEIGHT * map_zoom_factor
      map_width  = VIEW_AREA_MAP_WIDTH  * map_zoom_factor

      (0...map_height).each do |ay|
        my = ay + player.location.y - map_height/2
        draw_y = rect[1] + ay*map_block_size

        (0...map_width).each do |ax|

          mx = ax + player.location.x - map_width/2

          col = nil
          map.all_tiles_at( mx, my ) do |background, o, entity, s|
            col = nil
            col = COL_LIGHTGRAY   if background.blocked? 
            col = COL_YELLOW      if entity.kind_of?( DoorTile )
            col = COL_RED         if entity.kind_of?( Monster )
            col = COL_BLUE        if entity.kind_of?( Player )
          end
          if col then
            @screen.fill_rect(rect[0] + ax*map_block_size,
                              draw_y,
                              map_block_size,
                              map_block_size,
                              col)
          end   

        end

        # The center.
        @screen.draw_rect(rect[0] + map_width/2  * map_block_size,
                          rect[1] + map_height/2 * map_block_size,
                          map_block_size,
                          map_block_size,
                          COL_WHITE)

        flip if line_by_line

      end

    end



    ##
    # Helper for doing gradual buildup of image.
    # Draws the same thing twice, once for immediate viewing,
    # and on the offscreen buffer for next round.
    #
    def draw_immediately_twice
      yield
      @screen.flip
      yield
    end


    ##
    # Prepare a large sprite containing the scrolltext
    #
    def prepare_scrolltext( text )
      font = @font32
      textsize = font.text_size( text )

      @scrolltext = SDL::Surface.new(SDL::HWSURFACE, #|SDL::SRCCOLORKEY,
                                    textsize.first, textsize.last, @screen)

      @scrolltext.set_palette( SDL::LOGPAL|SDL::PHYSPAL, @sprite_palette, 0 )
      @scrolltext.setColorKey( SDL::SRCCOLORKEY || SDL::RLEACCEL ,0)


      font.drawBlendedUTF8( @scrolltext, text, 0, 0,  255, 255, 255 )
      @scrolltext_index = - @xsize
    end


    ##
    # Update the scrolltext area at the bottom of the screen.
    #
    def update_scrolltext
      
      @screen.fillRect( 0, 200 * SCALE_FACTOR, @xsize, 40 * SCALE_FACTOR, 0 )

      SDL.blit_surface( @scrolltext, 
                       @scrolltext_index, 0, @xsize, @scrolltext.h,
                       @screen, 0, 200 * SCALE_FACTOR )

      @scrolltext_index += 1 * SCALE_FACTOR

      if @scrolltext_index > @scrolltext.w + @xsize
        @scrolltext_index = - @xsize
      end

    end


    def setup_rotating_palette( range, screen = nil )
      pal = @sprite_palette
      if screen
        pal = @background_images[ screen ].get_palette
      end
      @rotating_palette = pal[ range ]
      @rotating_palette_range = range
    end

    ##
    #
    def rotate_palette # _ENABLED
      # DISABLED
    end
    def rotate_palette_DISABLED
      pal = @rotating_palette 
      col = pal.shift
      pal.push col

      @screen.set_palette( SDL::PHYSPAL|SDL::LOGPAL, pal, @rotating_palette_range.first )
    end

    ##
    # Prepare menu for rendering.
    #
    def setup_menu( entries, chosen = nil)
      @menu_items = entries

      max_width = 0
      total_height = 0
      font = @font32
      @menu_items.each do |text|
        tw, th = 16, 16 # font.text_size( text )
        max_width = [max_width,tw+16*SCALE_FACTOR].max
        total_height += th + 4*SCALE_FACTOR
      end
      @menu_width = max_width
      @menu_chosen_item = chosen || @menu_items.first
      
      # Truncate if the items can fit on screen.
      scr_height = 200 * SCALE_FACTOR
      if total_height > scr_height then
        @menu_height = scr_height
        @menu_truncate_size = (@menu_items.size * scr_height / (total_height)).to_i
      else
        @menu_height = total_height
        @menu_truncate_size = false 
      end
    end

    ##
    # This does a generic menu event loop
    #
    def choose_from_menu( menu_items = %w{OK Cancel}, input = nil )
      setup_menu(menu_items)
      begin
        draw_menu
        menu_event = input ? input.get_menu_item_navigation_event : yield
        if [:previous_menu_item, :next_menu_item].include?(menu_event) then
          self.send(menu_event)
        end
      end until [:exit_menu, :select_menu_item].include?(menu_event)
      erase_menu
      if menu_event == :select_menu_item then
        return menu_chosen_item
      else
        return false
      end
    end


    ##
    # Draw an updated menu.
    def draw_menu
      topx = 160 * SCALE_FACTOR - @menu_width  / (2)
      topy = 120 * SCALE_FACTOR - @menu_height / (2)

      #TODO: Save the old background.

      # Handle the case of truncated menu. Not too nice.
      if @menu_truncate_size then
        chosen_index = @menu_items.index(@menu_chosen_item)
        if chosen_index then
          half_trunc = @menu_truncate_size / 2
          first_item = [chosen_index-half_trunc, 0].max
          if first_item.zero?
            half_trunc += half_trunc - chosen_index
          end
          last_item  = [chosen_index+half_trunc, @menu_items.size].min

          curr_menu_items = @menu_items[first_item..last_item]
        else
          curr_menu_items = @menu_items[0..@menu_truncate_size]
        end
      else
        curr_menu_items = @menu_items
      end

      @screen.fillRect( topx, topy, @menu_width,@menu_height,0 )
      @screen.draw_rect( topx, topy, @menu_width,@menu_height, COL_GRAY )
      y_offset = topy
      font = @font32
      curr_menu_items.each do |text|
        tw, th = font.text_size( text )
        color_intensity = 127
        if text == @menu_chosen_item then
          rect = [ 
            topx + 4*SCALE_FACTOR, 
            y_offset + 4*SCALE_FACTOR,
            @menu_width - 8*SCALE_FACTOR, 
            font.height - 4*SCALE_FACTOR,
            COL_WHITE
          ]
          @screen.draw_rect( *rect )
          color_intensity = 255
        end
        write_smooth_text(text, 
                          topx + (@menu_width-tw)/2, 
                          y_offset + 2*SCALE_FACTOR, 
                          font, *[color_intensity]*3 )
        y_offset+= font.height + 4*SCALE_FACTOR
      end
      flip
    end

    attr_reader :menu_chosen_item

    def previous_menu_item
      @menu_chosen_item = 
        @menu_items[@menu_items.index(@menu_chosen_item)-1] ||
        @menu_items.last
    end

    def next_menu_item
      @menu_chosen_item = 
        @menu_items[@menu_items.index(@menu_chosen_item)+1] ||
        @menu_items.first
    end


    ##
    # Erase the menu.
    def erase_menu
      # TODO: Restore background
    end

  end # Graphics

end



# For testing
if $0 == __FILE__
  g = MagicMaze::Graphics.new

  command = ARGV.first

  case command
  when 'save_sprites'
    g.save_old_sprites 
  when 'load_spritemap'
    g.load_new_sprites
    pal = g.instance_eval{ @sprite_palette }
    p pal.class, pal.size
    pal.each{|line|
      puts
      line.each{|i| printf( "%02x ", i) if i.kind_of?(Numeric) }
    }
  end

end
