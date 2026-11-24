#include "../HostFrameworks/UIKit/LC32ClassicPresentationGeometry.h"
#include <cassert>
#include <cstdio>
#include <limits>

static bool near(CGFloat a, CGFloat b) { return std::abs(a - b) < 0.00001; }
int main() {
    CGFloat scale;
    assert(LC32ClassicPresentationScale(CGRectMake(0,0,320,568),
        CGRectMake(0,87.5,440,781), &scale) && near(scale,1.375));
    assert(!LC32ClassicPresentationScale(CGRectMake(0,0,320,568),
        CGRectMake(0,0,440,956), &scale)); // Lost host scaling, stale client scene.
    assert(!LC32ClassicPresentationScale(CGRectMake(0,0,440,956),
        CGRectMake(0,0,440,956), &scale)); // Full-screen is not Classic.
    assert(LC32ClassicPresentationScale(CGRectMake(0,0,320,568),
        CGRectMake(60,194,320,568), &scale) && near(scale,1)); // Unzoomed, centered.
    assert(!LC32ClassicPresentationScale(CGRectZero, CGRectMake(0,0,440,956), &scale));

    LC32ClassicWindowGeometry saved = {CGRectMake(0,0,320,568), CGPointMake(160,284),
        CGAffineTransformIdentity, CGRectMake(0,0,320,568), 1.375};
    CGPoint center;
    CGAffineTransform transform;
    const CGRect portrait = CGRectMake(0,0,440,956);
    assert(LC32ClassicWindowPlacement(saved, portrait, &center, &transform));
    assert(near(center.x,220) && near(center.y,478) && near(transform.a,1.375));
    // Repeating from the snapshot, not the previously applied transform,
    // must never multiply the zoom again.
    for(int i=0;i<10;++i) {
        assert(LC32ClassicWindowPlacement(saved, portrait, &center, &transform));
        assert(near(transform.a,1.375));
    }
    // A logical 3:4 canvas already scaled inside the same Classic window space.
    saved.bounds = CGRectMake(0,0,768,1024);
    saved.transform = CGAffineTransformMakeScale(320.0/768,320.0/768);
    assert(LC32ClassicWindowPlacement(saved, portrait, &center, &transform));
    assert(near(transform.a,440.0/768) && near(transform.a,transform.d));
    assert(near(center.x,220) && near(center.y,478));

    // Landscape backing coordinates and an authored transform/offset.
    saved = {CGRectMake(0,0,568,320), CGPointMake(294,155),
        CGAffineTransformMakeTranslation(3,-4), CGRectMake(0,0,568,320), 1.375};
    assert(LC32ClassicWindowPlacement(saved, CGRectMake(0,0,956,440), &center, &transform));
    assert(near(center.x,491.75) && near(center.y,213.125));
    assert(near(transform.tx,4.125) && near(transform.ty,-5.5));
    saved.transform = CGAffineTransformMakeRotation(M_PI_2);
    assert(LC32ClassicWindowPlacement(saved, CGRectMake(0,0,956,440), &center, &transform));
    assert(near(transform.a,0) && near(transform.b,1.375) &&
        near(transform.c,-1.375) && near(transform.d,0));
    saved.transform = CGAffineTransformIdentity;
    // A smaller captured Classic zoom remains smaller, not aspect-filled.
    saved.presentationScale=1;
    assert(LC32ClassicWindowPlacement(saved, CGRectMake(0,0,956,440), &center, &transform));
    assert(near(transform.a,1));
    saved.presentationScale=std::numeric_limits<double>::quiet_NaN();
    assert(!LC32ClassicWindowPlacement(saved, portrait, &center, &transform));
    saved.presentationScale=1;
    saved.transform.tx=std::numeric_limits<double>::infinity();
    assert(!LC32ClassicWindowPlacement(saved, portrait, &center, &transform));
    assert(!LC32ClassicWindowPlacement(saved, CGRectZero, &center, &transform));
    std::puts("Classic presentation geometry checks passed");
}
