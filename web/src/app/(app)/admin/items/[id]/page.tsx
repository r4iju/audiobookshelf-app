import { ItemManagementScreen } from "@/components/admin/item-management-screen";
export default async function ItemManagementPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  return <ItemManagementScreen itemId={decodeURIComponent(id)} />;
}
