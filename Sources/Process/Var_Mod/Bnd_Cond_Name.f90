!==============================================================================!
  character(len=80) function Var_Mod_Bnd_Cond_Name(phi, bnd_cell)
!------------------------------------------------------------------------------!
!   Provides a shortcut to obtain boundary condition name.                     !
!------------------------------------------------------------------------------!
  implicit none
!---------------------------------[Arguments]----------------------------------!
  type(Var_Type) :: phi
  integer        :: bnd_cell
!-----------------------------------[Locals]-----------------------------------!
  type(Grid_Type), pointer :: grid
!==============================================================================!

  grid => phi % pnt_grid

  Var_Mod_Bnd_Cond_Name =  &
       grid % bnd_cond % name(grid % bnd_cond % color(bnd_cell))

  end function

