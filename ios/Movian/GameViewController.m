//
//  GameViewController.m
//  Movian
//
//  Created by Andreas Öman on 03/06/15.
//  Copyright (c) 2015 Lonelycoder AB. All rights reserved.
//



#import "GameViewController.h"
#import <OpenGLES/ES2/glext.h>
#include <fenv.h>

#include "ui/glw/glw.h"
#include "ui/longpress.h"
#include "navigator.h"

@interface GameViewController () {
  lphelper_t longpress;
}
@property (strong, nonatomic) EAGLContext *context;
@property (nonatomic) glw_root_t *gr;
@property (nonatomic) CGPoint touch_start_pos;
@property (nonatomic) CGPoint touch_end_pos;
@property (nonatomic) NSTimeInterval touch_start_time;


- (void)setupGL;
- (void)tearDownGL;

@end

@implementation GameViewController

- (void)viewDidLoad
{
  [super viewDidLoad];
  
  self.context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];

  if (!self.context) {
    NSLog(@"Failed to create ES context");
  }
  
  GLKView *view = (GLKView *)self.view;
  view.context = self.context;
  view.drawableDepthFormat = GLKViewDrawableDepthFormat24;
  self.preferredFramesPerSecond = 60;

  [self setupGL];
  
  self.gr = calloc(1, sizeof(glw_root_t));
  glw_root_t *gr = self.gr;
  gr->gr_private = (__bridge void *)(self.context);
  gr->gr_prop_ui = prop_create_root("ui");
  gr->gr_prop_nav = nav_spawn();

  int flags = 0;
#if TARGET_OS_TV
  flags |= GLW_INIT_KEYBOARD_MODE | GLW_INIT_OVERSCAN | GLW_INIT_IN_FULLSCREEN;
#endif
  glw_init2(gr, flags);

  glw_opengl_init_context(gr);

  glw_lock(gr);
  glw_load_universe(gr);
  glw_unlock(gr);
  
#if TARGET_OS_TV == 1
  UISwipeGestureRecognizer *r;
  
  r = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(swipeRight:)];
  r.direction = UISwipeGestureRecognizerDirectionRight;
  [self.view addGestureRecognizer:r];
  
  r = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(swipeLeft:)];
  r.direction = UISwipeGestureRecognizerDirectionLeft;
  [self.view addGestureRecognizer:r];

  r = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(swipeUp:)];
  r.direction = UISwipeGestureRecognizerDirectionUp;
  [self.view addGestureRecognizer:r];

  r = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(swipeDown:)];
  r.direction = UISwipeGestureRecognizerDirectionDown;
  [self.view addGestureRecognizer:r];
#endif
}

- (void)dealloc
{    
    [self tearDownGL];
    
    if ([EAGLContext currentContext] == self.context) {
        [EAGLContext setCurrentContext:nil];
    }
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];

    if ([self isViewLoaded] && ([[self view] window] == nil)) {
        self.view = nil;
        
        [self tearDownGL];
        
        if ([EAGLContext currentContext] == self.context) {
            [EAGLContext setCurrentContext:nil];
        }
        self.context = nil;
    }

    // Dispose of any resources that can be recreated.
}

- (BOOL)prefersStatusBarHidden {
    return YES;
}

- (void)setupGL
{
    [EAGLContext setCurrentContext:self.context];
    
}

- (void)tearDownGL
{
    [EAGLContext setCurrentContext:self.context];
    
}

- (void)emitAction:(int)type
{
  glw_root_t *gr = self.gr;
  glw_lock(gr);

  event_t *e = event_create_action(type);
  e->e_flags |= EVENT_KEYPRESS;
  glw_inject_event(gr, e);
  glw_unlock(gr);
}


- (void)pressesBegan:(NSSet<UIPress *> *)presses withEvent:(UIPressesEvent *)event
{
  for(UIPress *press in presses) {
    
    switch(press.type) {
        
      case UIPressTypeUpArrow:
        [self emitAction:ACTION_UP];
        break;
      case UIPressTypeDownArrow:
        [self emitAction:ACTION_DOWN];
        break;
      case UIPressTypeLeftArrow:
        [self emitAction:ACTION_LEFT];
        break;
      case UIPressTypeRightArrow:
        [self emitAction:ACTION_RIGHT];
        break;
      case UIPressTypeSelect:
        longpress_down(&self->longpress);
        break;
      case UIPressTypeMenu:
        [self emitAction:ACTION_NAV_BACK];
        break;
      case UIPressTypePlayPause:
        [self emitAction:ACTION_PLAYPAUSE];
        break;

    }
  }
}


- (void)pressesEnded:(NSSet<UIPress *> *)presses withEvent:(UIPressesEvent *)event
{
  for(UIPress *press in presses) {
    
    if(press.type == UIPressTypeSelect) {
      if(longpress_up(&self->longpress)) {
        [self emitAction:ACTION_ACTIVATE];
        break;
      }
    }
  }
}

- (void)swipeLeft:(UISwipeGestureRecognizer *)sender
{
  [self emitAction:ACTION_LEFT];
}

- (void)swipeRight:(UISwipeGestureRecognizer *)sender
{
  [self emitAction:ACTION_RIGHT];
}

- (void)swipeUp:(UISwipeGestureRecognizer *)sender
{
  [self emitAction:ACTION_UP];
}

- (void)swipeDown:(UISwipeGestureRecognizer *)sender
{
  [self emitAction:ACTION_DOWN];
}



- (void)emitPointerEvent:(int) type withPoint:(CGPoint *)point time:(NSTimeInterval)ts
{
  glw_root_t *gr = self.gr;
  glw_lock(gr);
  glw_pointer_event_t gpe;
  
  const int height = [[self view] bounds].size.height;
  const int width  = [[self view] bounds].size.width;
  
  gpe.screen_x =  (2.0 * point->x / width)  - 1;
  gpe.screen_y = -(2.0 * point->y / height) + 1;
  gpe.ts = ts * 1000000.0;
  gpe.type = type;
  glw_pointer_event(gr, &gpe);
  glw_unlock(gr);
}


- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event
{
  if ([touches count] < 1) return;
  CGPoint point = [[touches anyObject] locationInView:[self view]];
  self.touch_start_pos = point;
  self.touch_start_time = event.timestamp;
    
//  printf("touch begin at %f,%f\n", point.x, point.y);
#if TARGET_OS_TV == 0
  [self emitPointerEvent:GLW_POINTER_TOUCH_START withPoint:&point time:event.timestamp];
#endif
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event
{
  if ([touches count] < 1) return;
  CGPoint point = [[touches anyObject] locationInView:[self view]];
#if 0
  CGFloat distance = sqrtf((point.x - self.touch_start_pos.x) * (point.x - self.touch_start_pos.x) +
                           (point.y - self.touch_start_pos.y) * (point.y - self.touch_start_pos.y));
  double delta_time = event.timestamp - self.touch_start_time;
//  printf("touch end at %f,%f distance=%f  delta-time=%f  speed: %f\n", point.x, point.y, distance, delta_time, distance / delta_time);
#endif
#if TARGET_OS_TV == 0
  [self emitPointerEvent:GLW_POINTER_TOUCH_MOVE withPoint:&point time:event.timestamp];
#endif
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event
{
  if ([touches count] < 1) return;
  CGPoint point = [[touches anyObject] locationInView:[self view]];


#if TARGET_OS_TV == 0
  [self emitPointerEvent:GLW_POINTER_TOUCH_END withPoint:&point time:event.timestamp];
#endif
}

- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event;
{
  if ([touches count] < 1) return;
  CGPoint point = [[touches anyObject] locationInView:[self view]];

#if TARGET_OS_TV == 0
  [self emitPointerEvent:GLW_POINTER_TOUCH_CANCEL withPoint:&point time:event.timestamp];
#endif
}




static void
denormal_ftz(void)
{
#ifdef FE_DFL_DISABLE_SSE_DENORMS_ENV
  fesetenv(FE_DFL_DISABLE_SSE_DENORMS_ENV);
#elif defined(__arm__)
  fenv_t env;
  fegetenv(&env);
  env.__fpscr |= __fpscr_flush_to_zero;
  fesetenv(&env);
#elif defined(__arm64__)
  fenv_t env;
  fegetenv(&env);
  env.__fpcr |= __fpcr_flush_to_zero;
  fesetenv(&env);
#else
#error No way to make denormals flush to zero
#endif
}





- (void)glkView:(GLKView *)view drawInRect:(CGRect)rect
{
  glw_root_t *gr = self.gr;

  denormal_ftz();
  
  glw_lock(gr);
  
  gr->gr_width  = (int)view.drawableWidth;
  gr->gr_height = (int)view.drawableHeight;
  
  glw_prepare_frame(self.gr, 0);

  int refresh = gr->gr_need_refresh;
  gr->gr_need_refresh = 0;
  if(gr->gr_width > 1 && gr->gr_height > 1 && gr->gr_universe) {
    
    if(refresh) {
      glw_rctx_t rc;
      int zmax = 0;
      glw_rctx_init(&rc, gr->gr_width, gr->gr_height, 1, &zmax);
      glw_layout0(gr->gr_universe, &rc);
      
      if(refresh & GLW_REFRESH_FLAG_RENDER) {
        glViewport(0, 0, gr->gr_width, gr->gr_height);
        glClear(GL_DEPTH_BUFFER_BIT | GL_COLOR_BUFFER_BIT);
        glw_render0(gr->gr_universe, &rc);
      }
    }
    
    glw_unlock(gr);
    if(refresh & GLW_REFRESH_FLAG_RENDER) {
      glw_post_scene(gr);
    }
    
  } else {
    glw_unlock(gr);
  }

  if(longpress_periodic(&self->longpress, gr->gr_frame_start)) {
    event_t *e = event_create_action(ACTION_ITEMMENU);
    e->e_flags |= EVENT_KEYPRESS;
    glw_inject_event(gr, e);
  }


}


@end
