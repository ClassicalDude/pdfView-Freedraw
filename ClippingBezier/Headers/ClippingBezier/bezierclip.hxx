/**************************************************************
 * 
 * Licensed to the Apache Software Foundation (ASF) under one
 * or more contributor license agreements.  See the NOTICE file
 * distributed with this work for additional information
 * regarding copyright ownership.  The ASF licenses this file
 * to you under the Apache License, Version 2.0 (the
 * "License"); you may not use this file except in compliance
 * with the License.  You may obtain a copy of the License at
 * 
 *   http://www.apache.org/licenses/LICENSE-2.0
 * 
 * Unless required by applicable law or agreed to in writing,
 * software distributed under the License is distributed on an
 * "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 * KIND, either express or implied.  See the License for the
 * specific language governing permissions and limitations
 * under the License.
 * 
 *************************************************************/


#ifndef BASEGFX_BEZIERCLIP_HXX
#define BASEGFX_BEZIERCLIP_HXX

#include <vector>

struct Point2D
{
    typedef double value_type;
    Point2D( double _x, double _y ) : x(_x), y(_y) {}
    Point2D() : x(), y() {}
    double x;
    double y;
};

struct Bezier
{
    Point2D	p0;
    Point2D	p1;
    Point2D	p2;
    Point2D	p3;

    Point2D& 		operator[]( int i ) { return reinterpret_cast<Point2D*>(this)[i]; }
    const Point2D& 	operator[]( int i ) const { return reinterpret_cast<const Point2D*>(this)[i]; }
};

struct FatLine
{
    // line L through p1 and p4 in normalized implicit form
    double a;
    double b;
    double c;

    // the upper and lower distance from this line
    double dMin;
    double dMax;
};

template <typename DataType> DataType calcLineDistance( const DataType& a,
                                                        const DataType& b,
                                                        const DataType& c,
                                                        const DataType& x,
                                                        const DataType& y )
{
    return a*x + b*y + c;
}

typedef ::std::vector< Point2D > Polygon2D;

/* little abs template */
template <typename NumType> NumType absval( NumType x )
{
    return x<0 ? -x : x;
}

Polygon2D convexHull( const Polygon2D& rPoly );

void clipBezier( ::std::back_insert_iterator< ::std::vector< ::std::pair<double, double> > >&	result,
                double 																		delta,
                struct Bezier& 																	c1,
                struct Bezier& 																	c2		  );

// TODO: find proper epsilon here (try ::std::numeric_limits<NumType>::epsilon()?)!
#ifndef DBL_EPSILON
#define DBL_EPSILON 1.0e-100
#endif

/* little approximate comparions */
template <typename NumType> bool tolZero( NumType n ) { return fabs(n) < DBL_EPSILON; }
template <typename NumType> bool tolEqual( NumType n1, NumType n2 ) { return tolZero(n1-n2); }
template <typename NumType> bool tolLessEqual( NumType n1, NumType n2 ) { return tolEqual(n1,n2) || n1<n2; }
template <typename NumType> bool tolGreaterEqual( NumType n1, NumType n2 ) { return tolEqual(n1,n2) || n1>n2; }

#endif /* BASEGFX_BEZIERCLIP_HXX */
