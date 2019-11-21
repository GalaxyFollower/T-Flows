!======================================================================!
  subroutine Multiphase_Mod_Compute_Vof(mult, sol, dt, n)
!----------------------------------------------------------------------!
!  Solves Volume Fraction equation using UPWIND ADVECTION and CICSAM   !
!----------------------------------------------------------------------!
!------------------------------[Modules]-------------------------------!
  use Const_Mod
  use Comm_Mod
  use Bulk_Mod,      only: Bulk_Type
  use Matrix_Mod,    only: Matrix_Type
!------------------------------------------------------------------------------!
!----------------------------------[Modules]-----------------------------------!
  use Work_Mod, only: beta_f => r_face_01, c_d => r_cell_01
!------------------------------------------------------------------------------!
  implicit none
!---------------------------------[Arguments]----------------------------------!
  type(Multiphase_Type), target :: mult
  type(Solver_Type),     target :: sol
  real                          :: dt
  integer                       :: n !Current temporal iteration
!-----------------------------------[Locals]-----------------------------------!
  type(Field_Type),  pointer :: flow
  type(Grid_Type),   pointer :: grid
  type(Bulk_Type),   pointer :: bulk
  type(Var_Type),    pointer :: vof
  real,              pointer :: vof_f(:)
  real,              pointer :: vof_i(:), vof_j(:), vof_k(:)
  type(Face_type),   pointer :: v_flux
  type(Matrix_Type), pointer :: a
  real,              pointer :: b(:)
  integer                    :: s, c, c1, c2
  integer                    :: exec_iter
  integer                    :: donor, accept, corr_num, corr_num_max
  integer                    :: i_sub, n_sub
  real                       :: fs, a0
  character(len=80)          :: solver
  character(len=1)           :: charI
  character(len=4)           :: charIter
  real                       :: upwd1, upwd2, upwd3, beta_const, eps_loc
  real                       :: courant_max, epsloc
  integer                    :: c1_glo, c2_glo
  logical                    :: corr_cicsam
!==============================================================================!

  call Cpu_Timer_Mod_Start('Compute_Multiphase (without solvers)')

  ! Take aliases
  flow   => mult % pnt_flow
  grid   => flow % pnt_grid
  bulk   => flow % bulk
  vof    => mult % vof
  vof_f  => mult % vof_f
  v_flux => flow % v_flux
  vof_i  => vof % x
  vof_j  => vof % y
  vof_k  => vof % z

  a => sol % a
  b => sol % b % val

  epsloc = epsilon(epsloc)

  if (vof % adv_scheme .eq. CICSAM .or. &
      vof % adv_scheme .eq. STACS) then
    ! Courant Number closeto the interface:
    call Vof_Max_Courant_Number(mult, dt, c_d, 1, courant_max, n)

    n_sub = min(max(ceiling(courant_max / 0.25),1),100)

    corr_num_max = 2
  else
    ! Old volume fraction:
    vof % o(:) = vof % n(:)
  end if

  if (vof % adv_scheme .eq. UPWIND) then
    !-------------------------!
    !   Matrix Coefficients   !
    !-------------------------!

    call Multiphase_Mod_Vof_Coefficients(flow, mult, a, b, dt, beta_f)   

    ! Get solver
    call Control_Mod_Solver_For_Multiphase(solver)

    ! Solve System
    call Multiphase_Mod_Vof_Solve_System(mult, sol, b)

    call Comm_Mod_Exchange_Real(grid, vof % n)

    !-----------------------------!
    !   Correct Volume Fraction   !
    !-----------------------------!

    do c = 1, grid % n_cells
      vof % n(c) = max(min(vof % n(c),1.0),0.0)
    end do

  else if (vof % adv_scheme .eq. CICSAM .or. &
           vof % adv_scheme .eq. STACS) then

    do i_sub = 1, n_sub

      ! Courant number full domain:
      call Vof_Max_Courant_Number(mult, dt / real(n_sub),    &
                                  c_d, 0, courant_max, n)

      ! Old volume fraction:
      vof % o(:) = vof % n(:)

      !---------------------------!
      !   Predict Beta at faces   !
      !---------------------------!
      ! Compute Gradient:
      call Grad_Mod_Variable(vof)

      call Multiphase_Mod_Vof_Predict_Beta(vof,                  &
                                           v_flux % n,           &
                                           vof_i, vof_j, vof_k,  &
                                           grid % dx,            &
                                           grid % dy,            &
                                           grid % dz,            &
                                           beta_f,               &
                                           c_d)

      loop_corr:  do corr_num = 1, corr_num_max
        !-------------------------!
        !   Matrix Coefficients   !
        !-------------------------!

        call Multiphase_Mod_Vof_Coefficients(flow, mult, a, b,          &
                                             dt / real(n_sub), beta_f)   
  
        ! Solve System
        call Multiphase_Mod_Vof_Solve_System(mult, sol, b)

        call Comm_Mod_Exchange_Real(grid, vof % n)

        !---------------------------!
        !   Correct Beta at faces   !
        !---------------------------!
        call Multiphase_Mod_Vof_Correct_Beta(vof,         &
                                             v_flux % n,  &
                                             beta_f,      &
                                             dt / real(n_sub))

        !------------------------!
        !   Correct Boundaries   !
        !------------------------!
        do s = 1, grid % n_faces

          c1 = grid % faces_c(1,s)
          c2 = grid % faces_c(2,s)

          if (c2 < 0) then
            if(Grid_Mod_Bnd_Cond_Type(grid,c2) .eq. OUTFLOW) then
              vof % n(c2) = max(min(vof % n(c1),1.0),0.0)
            end if
          end if

        end do

        !---------------------!
        !   Noise Reduction   !
        !---------------------!
        do c = 1, grid % n_cells
          if(vof % n(c) < epsloc) then
            vof % n(c) = 0.0
          end if

          if(1.0 - vof % n(c) < epsloc) then
            vof % n(c) = 1.0
          end if
        end do

      end do loop_corr

      !-----------------------------!
      !   Correct Volume Fraction   !
      !-----------------------------!
      do c = 1, grid % n_cells
        vof % n(c) = max(min(vof % n(c),1.0),0.0)
      end do

      call Comm_Mod_Exchange_Real(grid, vof % n)
    end do


  end if

  !-----------------------!
  !   Update properties   !
  !-----------------------!
  do c = 1, grid % n_cells
    density(c) = vof % n(c)         * phase_dens(1)         &
               + (1.0 - vof % n(c)) * phase_dens(2)
    viscosity(c) = vof % n(c)         * phase_visc(1)       &
                 + (1.0 - vof % n(c)) * phase_visc(2)
  end do

  call Comm_Mod_Exchange_Real(grid, density)
  call Comm_Mod_Exchange_Real(grid, viscosity)

  !------------------------------!
  !   Volume fraction at faces   !
  !------------------------------!

  if (vof % adv_scheme .eq. UPWIND) then

    do s = 1, grid % n_faces
      c1 = grid % faces_c(1,s)
      c2 = grid % faces_c(2,s)
      fs = grid % f(s)

      ! Face is inside the domain
      if(c2 > 0) then

        if (v_flux % n(s)>=0.0) then
          vof_f(s) = vof % n(c1) 
        else
          vof_f(s) = vof % n(c2) 
        end if

      ! Side is on the boundary
      else ! (c2 < 0)

        vof_f(s) = vof % n(c1)

      end if

    end do

  else if (vof % adv_scheme .eq. CICSAM .or. vof % adv_scheme .eq. STACS) then

    do s = 1, grid % n_faces
      c1 = grid % faces_c(1,s)
      c2 = grid % faces_c(2,s)
      fs = grid % f(s)

      c1_glo = grid % comm % cell_glo(c1)
      c2_glo = grid % comm % cell_glo(c2)

      if(c2 > 0) then
        if(v_flux % n(s) >= 0) then
          donor = c1
          accept = c2
        else
          donor = c2
          accept = c1
        end if

        vof_f(s) = 0.5 * ((1.0 - beta_f(s)) * ( vof % n(donor)      &
                                              + vof % o(donor) )    &
                               + beta_f(s)  * ( vof % n(accept)     &
                                              + vof % o(accept) ))

      else
        if(Grid_Mod_Bnd_Cond_Type(grid,c2) .eq. OUTFLOW) then
          vof_f(s) = vof % n(c1)
        else if(Grid_Mod_Bnd_Cond_Type(grid,c2) .eq. INFLOW) then
          vof_f(s) = vof % n(c2)
        else
          vof_f(s) = vof % n(c1)
        end if

      end if 
    end do

  end if

  !----------------------!
  !   Density at faces   !
  !----------------------!
  do s = 1, grid % n_faces
    dens_face(s) = vof_f(s) * phase_dens(1)  &
                 + (1.0 - vof_f(s)) * phase_dens(2)
  end do

  !----------------------------------------!
  !   Surface Tension Force Contribution   !
  !----------------------------------------!
  if (surface_tension > TINY ) then
    call Multiphase_Mod_Vof_Surface_Tension_Contribution(mult, n)
    call Grad_Mod_Variable(vof)
  end if

  call Cpu_Timer_Mod_Stop('Compute_Multiphase (without solvers)')

  call Grad_Mod_Variable(vof)
  call Compute_Benchmark(mult, dt)

  end subroutine
