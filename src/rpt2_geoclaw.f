! =====================================================
      subroutine rpt2(ixy,imp,maxm,meqn,mwaves,maux,mbc,mx,
     &                ql,qr,aux1,aux2,aux3,asdq,bmasdq,bpasdq)
! =====================================================
      use geoclaw_module, only: g => grav, tol => dry_tolerance
      use geoclaw_module, only: coordinate_system,earth_radius,deg2rad

      implicit none
!
!     Riemann solver in the transverse direction using 
!     Jacobian matrix from left cell (if imp==1) or right cell (if imp==2).
!
!     Note this has been modified from the version used in v5.7.0 and
!     earlier, where Roe averages based on ql and qr were used, which
!     is not correct.  In addition:
!      - a bug in the second component of the eigenvectors was fixed.
!      - when s(2) is close to zero this component of flux difference
!        is split equally between bmasdq and bpasdq to improve symmetry.
!   

!-----------------------last modified June 2020 ----------------------

      integer ixy,maxm,meqn,maux,mwaves,mbc,mx,imp

      double precision  ql(meqn,1-mbc:maxm+mbc)
      double precision  qr(meqn,1-mbc:maxm+mbc)
      double precision  asdq(meqn,1-mbc:maxm+mbc)
      double precision  bmasdq(meqn,1-mbc:maxm+mbc)
      double precision  bpasdq(meqn,1-mbc:maxm+mbc)
      double precision  aux1(maux,1-mbc:maxm+mbc)
      double precision  aux2(maux,1-mbc:maxm+mbc)
      double precision  aux3(maux,1-mbc:maxm+mbc)

      double precision  s(mwaves)
      double precision  r(meqn,mwaves)
      double precision  beta(mwaves)
      double precision  abs_tol
      double precision  hl,hr,hul,hur,hvl,hvr,vl,vr,ul,ur,bl,br
      double precision  ulr,hlr
      double precision  delf1,delf2,delf3,dxdcd,dxdcu
      double precision  dxdcm,dxdcp,topo1,topo3,eta

      integer i,m,mw,mu,mv
      
      abs_tol=tol

      if (ixy.eq.1) then
        mu = 2
        mv = 3
      else
        mu = 3
        mv = 2
      endif

      do i=2-mbc,mx+mbc

         hl=qr(1,i-1) 
         hr=ql(1,i) 
         hul=qr(mu,i-1) 
         hur=ql(mu,i) 
         hvl=qr(mv,i-1) 
         hvr=ql(mv,i)

!===========determine velocity from momentum===========================
       if (hl.lt.abs_tol) then
          hl=0.d0
          ul=0.d0
          vl=0.d0
       else
          ul=hul/hl
          vl=hvl/hl
       endif

       if (hr.lt.abs_tol) then
          hr=0.d0
          ur=0.d0
          vr=0.d0
       else
          ur=hur/hr
          vr=hvr/hr
       endif

       do mw=1,mwaves
          s(mw)=0.d0
          beta(mw)=0.d0
          do m=1,meqn
             r(m,mw)=0.d0
          enddo
       enddo
      dxdcp = 1.d0
      dxdcm = 1.d0

      if (hl <= tol .and. hr <= tol) go to 90

*      !check and see if cell that transverse waves are going in is high and dry
       if (imp.eq.1) then
            eta = qr(1,i-1)  + aux2(1,i-1)
            topo1 = aux1(1,i-1)
            topo3 = aux3(1,i-1)
       else
            eta = ql(1,i) + aux2(1,i)
            topo1 = aux1(1,i)
            topo3 = aux3(1,i)
       endif
       if (eta.lt.max(topo1,topo3)) go to 90

      if (coordinate_system.eq.2) then
         if (ixy.eq.2) then
             dxdcp=(earth_radius*deg2rad)
            dxdcm = dxdcp
         else
            if (imp.eq.1) then
               dxdcp = earth_radius*cos(aux3(3,i-1))*deg2rad
               dxdcm = earth_radius*cos(aux1(3,i-1))*deg2rad
            else
               dxdcp = earth_radius*cos(aux3(3,i))*deg2rad
               dxdcm = earth_radius*cos(aux1(3,i))*deg2rad
            endif
         endif
      endif

c=====Determine some speeds necessary for the Jacobian=================

            
            ! In v5.7.0 and prior versions,
            ! we used left right states to define Roe averages,
            ! which is consistent with those used in rpn2.
            ! But now we are computing upgoing, downgoing waves either in
            ! cell on left (if imp==1) or on right (if imp==2) so we
            ! should possibly use q values in cells above/below,
            ! but these aren't available (only aux values).
            ! At any rate, there is no clear justification for using cells
            ! on the other side of the normal-solve interface.

            ! Modified to use left or right state alone in defining
            ! Jacobian, based on imp:

            if (imp == 1) then
                ! asdq is leftgoing, use q from cell i-1:
                s(1) = vl-dsqrt(g*hl)
                s(2) = vl
                s(3) = vl+dsqrt(g*hl)
                ulr = ul
                hlr = hl
            else
                ! asdq is rightgoing, use q from cell i:
                s(1) = vr-dsqrt(g*hr)
                s(2) = vr
                s(3) = vr+dsqrt(g*hr)
                ulr = ur
                hlr = hr
            endif

c=======================Determine asdq decomposition (beta)============
         delf1=asdq(1,i)
         delf2=asdq(mu,i)
         delf3=asdq(mv, i)

         ! fixed bug in beta(2): ulr in place of s(2)=vlr
         beta(1) = (s(3)*delf1 - delf3) / (s(3) - s(1))
         beta(2) = -ulr*delf1 + delf2
         beta(3) = (delf3 - s(1)*delf1) / (s(3) - s(1))
c======================End =================================================

c=====================Set-up eigenvectors===================================
         r(1,1) = 1.d0
         r(2,1) = ulr    ! fixed bug, ulr not s(2)=vlr
         r(3,1) = s(1)

         r(1,2) = 0.d0
         r(2,2) = 1.d0
         r(3,2) = 0.d0

         r(1,3) = 1.d0
         r(2,3) = ulr    ! fixed bug, ulr not s(2)=vlr
         r(3,3) = s(3)
c============================================================================
90      continue
c============= compute fluctuations==========================================

          
         ! initialize all components to 0:
         bmasdq(:,:) = 0.d0
         bpasdq(:,:) = 0.d0
               
            do  mw=1,3
               if ((abs(s(mw)) > 0.d0) .and. 
     &             (abs(s(mw)) < 0.001d0*dsqrt(g*hlr))) then
                 ! split correction symmetrically if nearly zero
                 ! Note wave drops out if s(mw)==0 exactly, so no need to split
                 bmasdq(1,i) =bmasdq(1,i) +
     &                        0.5d0*dxdcm*s(mw)*beta(mw)*r(1,mw)
                 bmasdq(mu,i)=bmasdq(mu,i)+ 
     &                        0.5d0*dxdcm*s(mw)*beta(mw)*r(2,mw)
                 bmasdq(mv,i)=bmasdq(mv,i)+ 
     &                        0.5d0*dxdcm*s(mw)*beta(mw)*r(3,mw)
                 bpasdq(1,i) =bpasdq(1,i) + 
     &                        0.5d0*dxdcp*s(mw)*beta(mw)*r(1,mw)
                 bpasdq(mu,i)=bpasdq(mu,i)+ 
     &                        0.5d0*dxdcp*s(mw)*beta(mw)*r(2,mw)
                 bpasdq(mv,i)=bpasdq(mv,i)+ 
     &                        0.5d0*dxdcp*s(mw)*beta(mw)*r(3,mw)
               elseif (s(mw).lt.0.d0) then
                 bmasdq(1,i) =bmasdq(1,i) + dxdcm*s(mw)*beta(mw)*r(1,mw)
                 bmasdq(mu,i)=bmasdq(mu,i)+ dxdcm*s(mw)*beta(mw)*r(2,mw)
                 bmasdq(mv,i)=bmasdq(mv,i)+ dxdcm*s(mw)*beta(mw)*r(3,mw)
               elseif (s(mw).gt.0.d0) then
                 bpasdq(1,i) =bpasdq(1,i) + dxdcp*s(mw)*beta(mw)*r(1,mw)
                 bpasdq(mu,i)=bpasdq(mu,i)+ dxdcp*s(mw)*beta(mw)*r(2,mw)
                 bpasdq(mv,i)=bpasdq(mv,i)+ dxdcp*s(mw)*beta(mw)*r(3,mw)
               endif
            enddo
c========================================================================
         enddo
c

c

      return
      end
