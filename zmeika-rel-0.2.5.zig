const std = @import("std");
const sdl = @cImport({
    @cInclude("SDL2/SDL.h");
});

const WINDOW_WIDTH: i32 = 800;
const WINDOW_HEIGHT: i32 = 600;
const GRID_SIZE: i32 = 20;
const SNAKE_SPEED: f32 = 0.1;

const Direction = enum { up, down, left, right };

const Snake = struct {
    x: i32,
    y: i32,
    direction: Direction,
    body: std.ArrayList([2]i32),
    alive: bool,

    fn init(allocator: std.mem.Allocator) Snake {
        var body = std.ArrayList([2]i32).init(allocator);
        body.append([2]i32{ 10, 10 }) catch unreachable;
        return Snake{
            .x = 10,
            .y = 10,
            .direction = .right,
            .body = body,
            .alive = true,
        };
    }

    fn move(self: *Snake) void {
        const head = self.body.items[0];
        var new_head: [2]i32 = undefined;

        switch (self.direction) {
            .up => new_head = [2]i32{ head[0], head[1] - 1 },
            .down => new_head = [2]i32{ head[0], head[1] + 1 },
            .left => new_head = [2]i32{ head[0] - 1, head[1] },
            .right => new_head = [2]i32{ head[0] + 1, head[1] },
        }

        // Проверка на столкновение со стенами
        if (new_head[0] < 0 or new_head[0] >= WINDOW_WIDTH / GRID_SIZE or
            new_head[1] < 0 or new_head[1] >= WINDOW_HEIGHT / GRID_SIZE)
        {
            self.alive = false;
            return;
        }

        // Проверка на столкновение с собой
        for (self.body.items[1..]) |segment| {
            if (segment[0] == new_head[0] and segment[1] == new_head[1]) {
                self.alive = false;
                return;
            }
        }

        self.body.insert(0, new_head) catch unreachable;
        _ = self.body.pop(); // Удаляем хвост
    }

    fn grow(self: *Snake) void {
        const tail = self.body.items[self.body.items.len - 1];
        self.body.append(tail) catch unreachable;
    }

    fn setDirection(self: *Snake, dir: Direction) void {
        // Предотвращаем разворот на 180 градусов
        const can_change = switch (dir) {
            .up => self.direction != .down,
            .down => self.direction != .up,
            .left => self.direction != .right,
            .right => self.direction != .left,
        };
        if (can_change) self.direction = dir;
    }
};

const Food = struct {
    x: i32,
    y: i32,

    fn spawn(snake: Snake) Food {
        // var prng = std.rand.DefaultPrng.init(@bitCast(u64, std.time.nanoTimestamp()));
	// var prng = std.rand.DefaultPrng.init(@as(u64, @bitCast(std.time.nanoTimestamp())));
	// var prng = std.rand.DefaultPrng.init(@intCast(u64, std.time.nanoTimestamp()));
	// const seed: u64 = @truncate(std.time.nanoTimestamp());
        // var prng = std.rand.DefaultPrng.init(seed);
	const seed = @as(u64, @intCast(std.time.timestamp()));
        var prng = std.rand.DefaultPrng.init(seed);
        const rand = prng.random();
        while (true) {
            const x = rand.intRangeLessThan(i32, 0, WINDOW_WIDTH / GRID_SIZE);
            const y = rand.intRangeLessThan(i32, 0, WINDOW_HEIGHT / GRID_SIZE);
            var collides = false;
            for (snake.body.items) |segment| {
                if (segment[0] == x and segment[1] == y) {
                    collides = true;
                    break;
                }
            }
            if (!collides) return Food{ .x = x, .y = y };
        }
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    if (sdl.SDL_Init(sdl.SDL_INIT_VIDEO) < 0) {
        std.debug.print("SDL_Init Error: {s}\n", .{sdl.SDL_GetError()});
        return error.SDLInitializationFailed;
    }
    defer sdl.SDL_Quit();

    const window = sdl.SDL_CreateWindow("Zig Snake", sdl.SDL_WINDOWPOS_CENTERED, sdl.SDL_WINDOWPOS_CENTERED, WINDOW_WIDTH, WINDOW_HEIGHT, sdl.SDL_WINDOW_SHOWN) orelse {
        std.debug.print("SDL_CreateWindow Error: {s}\n", .{sdl.SDL_GetError()});
        return error.SDLWindowCreationFailed;
    };
    defer sdl.SDL_DestroyWindow(window);

    const renderer = sdl.SDL_CreateRenderer(window, -1, sdl.SDL_RENDERER_ACCELERATED) orelse {
        std.debug.print("SDL_CreateRenderer Error: {s}\n", .{sdl.SDL_GetError()});
        return error.SDLRendererCreationFailed;
    };
    defer sdl.SDL_DestroyRenderer(renderer);

    var snake = Snake.init(allocator);
    defer snake.body.deinit();
    var food = Food.spawn(snake);
    var frame_time: f32 = 0.0;

    var event: sdl.SDL_Event = undefined;
    var running = true;
    var game_over = false;

    while (running) {
        while (sdl.SDL_PollEvent(&event) != 0) {
            switch (event.type) {
                sdl.SDL_QUIT => running = false,
                sdl.SDL_KEYDOWN => {
                    switch (event.key.keysym.sym) {
                        sdl.SDLK_UP => snake.setDirection(.up),
                        sdl.SDLK_DOWN => snake.setDirection(.down),
                        sdl.SDLK_LEFT => snake.setDirection(.left),
                        sdl.SDLK_RIGHT => snake.setDirection(.right),
                        sdl.SDLK_q => running = false,
                        else => {},
                    }
                },
                else => {},
            }
        }

        const current_time = @as(f32, @floatFromInt(sdl.SDL_GetTicks())) / 1000.0;
        if (current_time - frame_time >= SNAKE_SPEED and snake.alive) {
            snake.move();

            // Проверка на съедение еды
            const head = snake.body.items[0];
            if (head[0] == food.x and head[1] == food.y) {
                snake.grow();
                food = Food.spawn(snake);
            }

            frame_time = current_time;
        }

        // Отрисовка
        _ = sdl.SDL_SetRenderDrawColor(renderer, 0, 0, 0, 255); // Черный фон
        _ = sdl.SDL_RenderClear(renderer);

        _ = sdl.SDL_SetRenderDrawColor(renderer, 0, 255, 0, 255); // Зеленая змейка
        for (snake.body.items) |segment| {
            const rect = sdl.SDL_Rect{
                .x = segment[0] * GRID_SIZE,
                .y = segment[1] * GRID_SIZE,
                .w = GRID_SIZE - 1,
                .h = GRID_SIZE - 1,
            };
            _ = sdl.SDL_RenderFillRect(renderer, &rect);
        }

        _ = sdl.SDL_SetRenderDrawColor(renderer, 255, 0, 0, 255); // Красная еда
        const food_rect = sdl.SDL_Rect{
            .x = food.x * GRID_SIZE,
            .y = food.y * GRID_SIZE,
            .w = GRID_SIZE - 1,
            .h = GRID_SIZE - 1,
        };
        _ = sdl.SDL_RenderFillRect(renderer, &food_rect);

        sdl.SDL_RenderPresent(renderer);

        if (!snake.alive and !game_over) {
            std.debug.print("Game Over! Press 'q' to quit.\n", .{});
            game_over = true;
        }
    }
}
