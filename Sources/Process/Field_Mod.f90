!==============================================================================!
  module Field_Mod
!------------------------------------------------------------------------------!
!   Module for basic flow field plus temperature.                              !
!   It is a bit of a mumbo-jumbo at this moment, it will furhter have to       !
!   differentiate into numerical and physica parts.                            !
!------------------------------------------------------------------------------!
!----------------------------------[Modules]-----------------------------------!
  use Var_Mod
!------------------------------------------------------------------------------!
  implicit none
!==============================================================================!

  !----------------!
  !   Field type   !
  !----------------!
  type Field_Type

    type(Grid_Type), pointer :: pnt_grid  ! grid for which it is defined

    ! Velocity components
    type(Var_Type) :: u
    type(Var_Type) :: v
    type(Var_Type) :: w

    ! Temperature
    type(Var_Type) :: t

    ! Pressure 
    type(Var_Type) :: p
    type(Var_Type) :: pp

    ! Mass fluxes throught cell faces
    real, allocatable :: flux(:)

    ! Reference temperature
    real :: t_ref

  end type

  ! Variables determining if we are dealing with heat transfer and buoyancy
  logical :: heat_transfer
  logical :: buoyancy

  ! Physical properties
  real :: viscosity, density, conductivity, diffusivity, capacity

  ! Angular velocity 
  real :: omega_x, omega_y, omega_z, omega

  ! Gravity
  real :: grav_x, grav_y, grav_z

  contains

  include 'Field_Mod/Allocate.f90'

  end module
